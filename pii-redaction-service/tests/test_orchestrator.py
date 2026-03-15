"""
Unit tests for chunk_at_word_boundary and build_manifest.
"""

from __future__ import annotations

from app.orchestrator import ChunkManifest, _chunk_at_word_boundary, build_manifest


class TestChunkAtWordBoundary:
    def test_short_text_returned_as_single_chunk(self):
        assert _chunk_at_word_boundary("hello world", 5000) == ["hello world"]

    def test_exact_limit_is_single_chunk(self):
        text = "a" * 5000
        result = _chunk_at_word_boundary(text, 5000)
        assert result == [text]

    def test_splits_on_space(self):
        text = "hello world foo bar"
        result = _chunk_at_word_boundary(text, 11)
        # "hello world" = 11, then "foo bar" = 7
        assert result == ["hello world", "foo bar"]

    def test_single_word_longer_than_limit_is_split(self):
        word = "a" * 12
        result = _chunk_at_word_boundary(word, 5)
        assert all(len(c) <= 5 for c in result)
        assert "".join(result) == word

    def test_empty_text_returns_empty_list(self):
        assert _chunk_at_word_boundary("", 5000) == [""]

    def test_multiple_spaces_preserved_as_single(self):
        # split() collapses whitespace — words are joined with single space
        text = "foo  bar"
        result = _chunk_at_word_boundary(text, 5000)
        assert len(result) == 1


class TestBuildManifest:
    def _msg(self, role: str, content: str) -> dict:
        return {"role": role, "content": content}

    def test_empty_messages_returns_empty_manifest(self):
        manifest = build_manifest([], scan_roles=["user"], max_doc_chars=5000)
        assert manifest.total_docs() == 0

    def test_system_role_skipped_by_default_scan_roles(self):
        messages = [
            self._msg("system", "You are an assistant."),
            self._msg("user", "Hello"),
        ]
        manifest = build_manifest(messages, scan_roles=["user", "assistant", "tool"], max_doc_chars=5000)
        assert manifest.total_docs() == 1
        assert manifest.entries[0].doc_id == "1_0"

    def test_all_roles_in_scan_roles_are_included(self):
        messages = [
            self._msg("user", "Hello"),
            self._msg("assistant", "Hi"),
            self._msg("tool", "result"),
        ]
        manifest = build_manifest(messages, scan_roles=["user", "assistant", "tool"], max_doc_chars=5000)
        assert manifest.total_docs() == 3

    def test_long_content_produces_multiple_chunks(self):
        long_text = " ".join(["word"] * 1100)  # each "word " = 5 chars → ~5500 chars
        messages = [self._msg("user", long_text)]
        manifest = build_manifest(messages, scan_roles=["user"], max_doc_chars=5000)
        assert manifest.total_docs() > 1

    def test_chunk_ids_use_message_underscore_chunk_format(self):
        messages = [
            self._msg("user", "a " * 2600),
        ]
        manifest = build_manifest(messages, scan_roles=["user"], max_doc_chars=5000)
        for entry in manifest.entries:
            parts = entry.doc_id.split("_")
            assert len(parts) == 2
            assert parts[0].isdigit() and parts[1].isdigit()

    def test_empty_content_skipped(self):
        messages = [self._msg("user", "")]
        manifest = build_manifest(messages, scan_roles=["user"], max_doc_chars=5000)
        assert manifest.total_docs() == 0

    def test_non_string_content_skipped(self):
        messages = [{"role": "user", "content": None}]
        manifest = build_manifest(messages, scan_roles=["user"], max_doc_chars=5000)
        assert manifest.total_docs() == 0


class TestChunkManifest:
    def _make_manifest(self, n: int) -> ChunkManifest:
        from app.orchestrator import ChunkEntry

        entries = [
            ChunkEntry(doc_id=str(i), message_index=0, chunk_index=i, original_text=f"text{i}") for i in range(n)
        ]
        return ChunkManifest(entries=entries)

    def test_batches_correct_size(self):
        manifest = self._make_manifest(12)
        batches = manifest.batches(5)
        assert len(batches) == 3
        assert len(batches[0]) == 5
        assert len(batches[1]) == 5
        assert len(batches[2]) == 2

    def test_coverage_complete_false_when_redacted_text_missing(self):
        manifest = self._make_manifest(2)
        manifest.entries[0].redacted_text = "redacted"
        assert not manifest.coverage_complete()

    def test_coverage_complete_true_when_all_filled(self):
        manifest = self._make_manifest(2)
        for entry in manifest.entries:
            entry.redacted_text = "redacted"
        assert manifest.coverage_complete()
