"""
Unit tests for chunk_at_word_boundary and build_manifest.
"""

from __future__ import annotations

from app.orchestrator import ChunkManifest, _chunk_at_word_boundary, build_manifest


class TestChunkAtWordBoundary:
    def test_short_text_returned_as_single_chunk(self):
        # Given text shorter than the configured limit.
        # When the text is chunked.
        # Then a single unchanged chunk is returned.
        assert _chunk_at_word_boundary("hello world", 5000) == ["hello world"]

    def test_exact_limit_is_single_chunk(self):
        # Given text exactly at the configured limit.
        text = "a" * 5000

        # When the text is chunked.
        result = _chunk_at_word_boundary(text, 5000)

        # Then the full text remains in a single chunk.
        assert result == [text]

    def test_splits_on_space(self):
        # Given text that can be split cleanly on whitespace.
        text = "hello world foo bar"

        # When the text is chunked with a small max length.
        result = _chunk_at_word_boundary(text, 11)

        # Then whole words are preserved across chunk boundaries.
        # "hello world" = 11, then "foo bar" = 7
        assert result == ["hello world", "foo bar"]

    def test_single_word_longer_than_limit_is_split(self):
        # Given a single word that exceeds the max length.
        word = "a" * 12

        # When the text is chunked.
        result = _chunk_at_word_boundary(word, 5)

        # Then the word is split into bounded chunks without losing characters.
        assert all(len(c) <= 5 for c in result)
        assert "".join(result) == word

    def test_empty_text_returns_empty_list(self):
        # Given an empty string.
        # When the text is chunked.
        # Then a single empty chunk is returned.
        assert _chunk_at_word_boundary("", 5000) == [""]

    def test_multiple_spaces_preserved_as_single(self):
        # Given text containing repeated whitespace.
        # split() collapses whitespace — words are joined with single space
        text = "foo  bar"

        # When the text is chunked.
        result = _chunk_at_word_boundary(text, 5000)

        # Then the normalized chunk list still contains a single chunk.
        assert len(result) == 1


class TestBuildManifest:
    def _msg(self, role: str, content: str) -> dict:
        return {"role": role, "content": content}

    def test_empty_messages_returns_empty_manifest(self):
        # Given no messages to scan.
        manifest = build_manifest([], scan_roles=["user"], max_doc_chars=5000)

        # When the manifest is built.
        # Then it contains no documents.
        assert manifest.total_docs() == 0

    def test_system_role_skipped_by_default_scan_roles(self):
        # Given a system message and a user message.
        messages = [
            self._msg("system", "You are an assistant."),
            self._msg("user", "Hello"),
        ]

        # When the manifest is built for user, assistant, and tool roles.
        manifest = build_manifest(messages, scan_roles=["user", "assistant", "tool"], max_doc_chars=5000)

        # Then only the user message is included in the manifest.
        assert manifest.total_docs() == 1
        assert manifest.entries[0].doc_id == "1_0"

    def test_all_roles_in_scan_roles_are_included(self):
        # Given messages for every configured scan role.
        messages = [
            self._msg("user", "Hello"),
            self._msg("assistant", "Hi"),
            self._msg("tool", "result"),
        ]

        # When the manifest is built.
        manifest = build_manifest(messages, scan_roles=["user", "assistant", "tool"], max_doc_chars=5000)

        # Then each message contributes one document.
        assert manifest.total_docs() == 3

    def test_long_content_produces_multiple_chunks(self):
        # Given one message that exceeds the document size limit.
        long_text = " ".join(["word"] * 1100)  # each "word " = 5 chars → ~5500 chars
        messages = [self._msg("user", long_text)]

        # When the manifest is built.
        manifest = build_manifest(messages, scan_roles=["user"], max_doc_chars=5000)

        # Then multiple chunk entries are created.
        assert manifest.total_docs() > 1

    def test_chunk_ids_use_message_underscore_chunk_format(self):
        # Given one message that is long enough to produce multiple chunks.
        messages = [
            self._msg("user", "a " * 2600),
        ]

        # When the manifest is built.
        manifest = build_manifest(messages, scan_roles=["user"], max_doc_chars=5000)

        # Then each generated doc id follows the message_chunk pattern.
        for entry in manifest.entries:
            parts = entry.doc_id.split("_")
            assert len(parts) == 2
            assert parts[0].isdigit() and parts[1].isdigit()

    def test_empty_content_skipped(self):
        # Given a message with empty content.
        messages = [self._msg("user", "")]

        # When the manifest is built.
        manifest = build_manifest(messages, scan_roles=["user"], max_doc_chars=5000)

        # Then no documents are emitted.
        assert manifest.total_docs() == 0

    def test_non_string_content_skipped(self):
        # Given a message with non-string content.
        messages = [{"role": "user", "content": None}]

        # When the manifest is built.
        manifest = build_manifest(messages, scan_roles=["user"], max_doc_chars=5000)

        # Then the invalid message is skipped.
        assert manifest.total_docs() == 0


class TestChunkManifest:
    def _make_manifest(self, n: int) -> ChunkManifest:
        from app.orchestrator import ChunkEntry

        entries = [
            ChunkEntry(doc_id=str(i), message_index=0, chunk_index=i, original_text=f"text{i}") for i in range(n)
        ]
        return ChunkManifest(entries=entries)

    def test_batches_correct_size(self):
        # Given a manifest with 12 entries.
        manifest = self._make_manifest(12)

        # When batches are requested in groups of 5.
        batches = manifest.batches(5)

        # Then the final batch contains the remainder.
        assert len(batches) == 3
        assert len(batches[0]) == 5
        assert len(batches[1]) == 5
        assert len(batches[2]) == 2

    def test_coverage_complete_false_when_redacted_text_missing(self):
        # Given a manifest where only one entry has redacted text.
        manifest = self._make_manifest(2)
        manifest.entries[0].redacted_text = "redacted"

        # When coverage is checked.
        # Then the manifest is considered incomplete.
        assert not manifest.coverage_complete()

    def test_coverage_complete_true_when_all_filled(self):
        # Given a manifest where all entries have redacted text.
        manifest = self._make_manifest(2)
        for entry in manifest.entries:
            entry.redacted_text = "redacted"

        # When coverage is checked.
        # Then the manifest is considered complete.
        assert manifest.coverage_complete()
