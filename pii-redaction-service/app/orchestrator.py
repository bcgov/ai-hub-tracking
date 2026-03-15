"""
Orchestration logic for PII redaction of chat completion payloads.

Design:
  1. Manifest phase  — walk messages, chunk content at word boundaries, record
                       every (messageIndex, chunkIndex, text) triple.
  2. Batch phase     — group chunks into batches of MAX_DOCS_PER_CALL, submit all
                       batches concurrently (Semaphore-bounded to MAX_BATCH_CONCURRENCY
                       in-flight) within the APIM timeout budget.  Reject if >
                       MAX_CONCURRENT_BATCHES.
  3. Reassemble phase — apply redacted text from each chunk result back onto the
                        original messages; verify full coverage.
  4. Return          — RedactionSuccess or RedactionFailure depending on coverage
                       disposition and fail_closed flag.

Chunk IDs follow the same convention as the existing APIM fragment:
  "<messageIndex>_<chunkIndex>"
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any

from .config import Settings
from .language_client import LanguageClient
from .models import (
    Diagnostics,
    RedactionConfig,
    RedactionFailure,
    RedactionRequest,
    RedactionSuccess,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Chunk manifest data structures
# ---------------------------------------------------------------------------


@dataclass
class ChunkEntry:
    doc_id: str  # "<messageIndex>_<chunkIndex>"
    message_index: int
    chunk_index: int
    original_text: str
    redacted_text: str | None = None


@dataclass
class ChunkManifest:
    entries: list[ChunkEntry] = field(default_factory=list)
    skipped_roles: set[str] = field(default_factory=set)

    def total_docs(self) -> int:
        return len(self.entries)

    def batches(self, batch_size: int) -> list[list[ChunkEntry]]:
        return [self.entries[i : i + batch_size] for i in range(0, len(self.entries), batch_size)]

    def coverage_complete(self) -> bool:
        return all(e.redacted_text is not None for e in self.entries)


# ---------------------------------------------------------------------------
# Chunking
# ---------------------------------------------------------------------------


def _chunk_at_word_boundary(text: str, max_chars: int) -> list[str]:
    """
    Split *text* into chunks that never exceed *max_chars* characters,
    breaking only on whitespace boundaries.

    If a single word exceeds *max_chars* (e.g. base64 blob) it is split into
    multiple *max_chars*-sized chunks to avoid infinite loops.

        Notes:
            - We split specifically on the literal space character because chat
                payloads are plain text and the downstream reassembly logic restores
                inter-chunk spacing with a single-space join.
            - Oversized words are the only case where we break within a token.
    """
    if len(text) <= max_chars:
        return [text]

    chunks: list[str] = []
    words = text.split(" ")
    current = ""

    for word in words:
        candidate = (current + " " + word).lstrip() if current else word
        if len(candidate) > max_chars:
            if current:
                chunks.append(current)
            # Handle words longer than max_chars
            while len(word) > max_chars:
                chunks.append(word[:max_chars])
                word = word[max_chars:]
            current = word
        else:
            current = candidate

    if current:
        chunks.append(current)

    return chunks


def build_manifest(
    messages: list[dict[str, Any]],
    scan_roles: list[str],
    max_doc_chars: int,
) -> ChunkManifest:
    """
    Walk messages, skip roles not in *scan_roles*, chunk content, and
    return a populated ChunkManifest.

    Each chunk receives a deterministic ``<messageIndex>_<chunkIndex>`` id so
    batch responses can be mapped back to the original message content without
    relying on list position.
    """
    manifest = ChunkManifest()
    for msg_idx, message in enumerate(messages):
        role = message.get("role", "")
        content = message.get("content", "")
        if role not in scan_roles:
            if role:
                manifest.skipped_roles.add(role)
            continue
        if not isinstance(content, str) or not content:
            continue
        chunks = _chunk_at_word_boundary(content, max_doc_chars)
        for chunk_idx, chunk_text in enumerate(chunks):
            manifest.entries.append(
                ChunkEntry(
                    doc_id=f"{msg_idx}_{chunk_idx}",
                    message_index=msg_idx,
                    chunk_index=chunk_idx,
                    original_text=chunk_text,
                )
            )
    return manifest


# ---------------------------------------------------------------------------
# Batch execution
# ---------------------------------------------------------------------------


async def _run_batch(
    client: LanguageClient,
    batch: list[ChunkEntry],
    language: str,
    excluded_categories: list[str],
) -> tuple[dict[str, str], int]:
    """
    Send one batch to the Language API and return a map of doc_id → redacted text.
    """
    documents = [{"id": e.doc_id, "text": e.original_text} for e in batch]
    response = await client.analyze_pii(
        documents=documents,
        language=language,
        excluded_categories=excluded_categories or None,
    )

    redacted: dict[str, str] = {}
    entity_count = 0
    for doc in response.get("results", {}).get("documents", []):
        redacted[doc["id"]] = doc.get("redactedText", "")
        entity_count += len(doc.get("entities", []))

    return redacted, entity_count


async def _run_batch_with_semaphore(
    sem: asyncio.Semaphore,
    client: LanguageClient,
    batch: list[ChunkEntry],
    language: str,
    excluded_categories: list[str],
    per_batch_timeout: float,
) -> tuple[dict[str, str], int]:
    """
    Acquire a semaphore slot, then execute one Language API batch.

        Why the semaphore exists:
            - A single request may expand into many Language API batches.
            - We do not want all of those HTTP calls to start at once because that
                would create an unbounded fan-out against the Language API.
            - ``sem`` limits how many batch calls from this request are allowed to be
                in flight simultaneously.

        How to read the two limits involved here:
            - ``max_concurrent_batches`` is a request-size guard. It caps how many
                batches a request is allowed to require at all.
            - ``max_batch_concurrency`` is the worker-pool size. It controls how many
                of those allowed batches can actively execute at the same time.

    The per-batch timeout applies only to the outbound API call after a worker
    slot is acquired. Waiting on the semaphore is governed by the outer,
    end-to-end request deadline in ``orchestrate_redaction``.

        Example with ``max_batch_concurrency = 3``:
            - If a request produces 8 batches, batches 1-3 start immediately.
            - Batches 4-8 wait for one of those three slots to free up.
            - Each running batch gets its own per-batch timeout.
            - The whole request, including time spent waiting for a slot, must still
                finish before the outer request deadline expires.
    """
    async with sem:
        return await asyncio.wait_for(
            _run_batch(client, batch, language, excluded_categories),
            timeout=per_batch_timeout,
        )


# ---------------------------------------------------------------------------
# Reassembly
# ---------------------------------------------------------------------------


def _reassemble_messages(
    original_messages: list[dict[str, Any]],
    manifest: ChunkManifest,
) -> list[dict[str, Any]]:
    """
    Merge redacted chunk text back into the original messages list.
    Chunks for the same message are concatenated with a single-space separator
    (matching the whitespace consumed by ``text.split(" ")`` in chunking).

    Messages that were skipped during manifest construction are returned
    unchanged.
    """
    # Group chunks by message index (preserving insertion order)
    grouped: dict[int, list[ChunkEntry]] = defaultdict(list)
    for entry in manifest.entries:
        grouped[entry.message_index].append(entry)

    reassembled = []
    for idx, message in enumerate(original_messages):
        if idx not in grouped:
            reassembled.append(message)
            continue
        chunks = sorted(grouped[idx], key=lambda e: e.chunk_index)
        redacted_parts = [c.redacted_text or c.original_text for c in chunks]
        reassembled.append({**message, "content": " ".join(redacted_parts)})

    return reassembled


# ---------------------------------------------------------------------------
# Main orchestrator entry point
# ---------------------------------------------------------------------------


async def orchestrate_redaction(
    request: RedactionRequest,
    client: LanguageClient,
    settings: Settings,
) -> RedactionSuccess | RedactionFailure:
    """
    Full redaction pipeline: manifest → batch → reassemble → verify coverage.
    """
    start = time.monotonic()
    config: RedactionConfig = request.config
    messages_raw = [m.model_dump() for m in request.body.messages]

    # 1. Build chunk manifest
    manifest = build_manifest(
        messages=messages_raw,
        scan_roles=config.scan_roles,
        max_doc_chars=settings.max_doc_chars,
    )

    total_docs = manifest.total_docs()
    skipped = sorted(manifest.skipped_roles)
    if total_docs == 0:
        # Nothing to redact — return body unchanged
        elapsed = (time.monotonic() - start) * 1000
        return RedactionSuccess(
            full_coverage=True,
            redacted_body={
                "messages": messages_raw,
                **request.body.model_extra_dict(),
            },
            diagnostics=Diagnostics(
                total_docs=0,
                total_batches=0,
                elapsed_ms=elapsed,
                skipped_roles=skipped,
            ),
        )

    batches = manifest.batches(settings.max_docs_per_call)
    total_batches = len(batches)

    if total_batches > settings.max_concurrent_batches:
        elapsed = (time.monotonic() - start) * 1000
        msg = (
            f"Payload requires {total_batches} batches which exceeds the maximum "
            f"of {settings.max_concurrent_batches}. Rejecting."
        )
        logger.warning(
            msg,
            extra={
                "total_batches": total_batches,
                "max_batches": settings.max_concurrent_batches,
                "correlation_id": config.correlation_id,
            },
        )
        return RedactionFailure(
            status="payload-too-large",
            error=msg,
            diagnostics=Diagnostics(
                total_docs=total_docs,
                total_batches=total_batches,
                elapsed_ms=elapsed,
                skipped_roles=skipped,
            ),
        )

    # 2. Execute batches concurrently (semaphore-bounded) — honouring total timeout
    deadline = start + settings.total_processing_timeout_seconds

    # This semaphore acts like a small per-request worker pool. It prevents one
    # large payload from launching every Language API call at once, while still
    # allowing limited parallelism to keep total latency acceptable.
    sem = asyncio.Semaphore(settings.max_batch_concurrency)
    remaining = deadline - time.monotonic()

    try:
        # The outer wait_for enforces the full request budget across both
        # queued and in-flight batch tasks.
        batch_results: list[tuple[dict[str, str], int] | BaseException] = await asyncio.wait_for(
            asyncio.gather(
                *[
                    _run_batch_with_semaphore(
                        sem,
                        client,
                        batch,
                        config.detection_language,
                        config.excluded_categories,
                        settings.per_batch_timeout_seconds,
                    )
                    for batch in batches
                ],
                return_exceptions=True,
            ),
            timeout=remaining,
        )
    except TimeoutError:
        elapsed = (time.monotonic() - start) * 1000
        return RedactionFailure(
            error="Total processing timeout exceeded",
            diagnostics=Diagnostics(
                total_docs=total_docs,
                total_batches=total_batches,
                elapsed_ms=elapsed,
                skipped_roles=skipped,
            ),
        )

    total_entity_count = 0
    for batch_num, (batch, result) in enumerate(zip(batches, batch_results), start=1):
        if isinstance(result, BaseException):
            elapsed = (time.monotonic() - start) * 1000
            error_msg = (
                f"Batch {batch_num}/{total_batches} timed out"
                if isinstance(result, TimeoutError)
                else f"Language API error in batch {batch_num}/{total_batches}: {result}"
            )
            logger.error(
                error_msg,
                extra={"correlation_id": config.correlation_id},
            )
            return RedactionFailure(
                error=error_msg,
                diagnostics=Diagnostics(
                    total_docs=total_docs,
                    total_batches=total_batches,
                    elapsed_ms=elapsed,
                    entity_count=total_entity_count,
                    skipped_roles=skipped,
                ),
            )
        redacted_map, batch_entity_count = result
        total_entity_count += batch_entity_count
        # Copy redacted text back onto the manifest entries so coverage and
        # reassembly both operate on the same source of truth.
        for entry in batch:
            entry.redacted_text = redacted_map.get(entry.doc_id)

    logger.debug(
        "All %d batches complete",
        total_batches,
        extra={"correlation_id": config.correlation_id},
    )

    # 3. Verify coverage
    elapsed = (time.monotonic() - start) * 1000

    if not manifest.coverage_complete():
        missing = [e.doc_id for e in manifest.entries if e.redacted_text is None]
        logger.warning(
            "Incomplete PII coverage: %d chunk(s) missing redacted text",
            len(missing),
            extra={"missing_ids": missing, "correlation_id": config.correlation_id},
        )
        return RedactionFailure(
            error=f"Incomplete coverage: missing redacted text for {len(missing)} chunk(s)",
            diagnostics=Diagnostics(
                total_docs=total_docs,
                total_batches=total_batches,
                elapsed_ms=elapsed,
                entity_count=total_entity_count,
                skipped_roles=skipped,
            ),
        )

    # 4. Reassemble
    redacted_messages = _reassemble_messages(messages_raw, manifest)
    return RedactionSuccess(
        full_coverage=True,
        redacted_body={
            "messages": redacted_messages,
            **request.body.model_extra_dict(),
        },
        diagnostics=Diagnostics(
            total_docs=total_docs,
            total_batches=total_batches,
            elapsed_ms=elapsed,
            entity_count=total_entity_count,
            skipped_roles=skipped,
        ),
    )
