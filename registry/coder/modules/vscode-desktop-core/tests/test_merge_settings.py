import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "merge-settings.py"


class MergeSettingsTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.existing = self.directory / "existing.json"
        self.configured = self.directory / "configured.json"
        self.output = self.directory / "merged.json"
        self.configured.write_text("{}", encoding="utf-8")

    def run_merge(self):
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                str(self.existing),
                str(self.configured),
                str(self.output),
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_merge(self, source, configured, expected):
        self.existing.write_text(source, encoding="utf-8")
        self.configured.write_text(json.dumps(configured), encoding="utf-8")
        original = self.existing.read_bytes()
        result = self.run_merge()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(json.loads(self.output.read_text(encoding="utf-8")), expected)
        self.assertTrue(self.output.read_bytes().endswith(b"\n"))
        self.assertEqual(self.existing.read_bytes(), original)

    def assert_rejected(self, source, message):
        self.existing.write_bytes(source)
        self.output.write_bytes(b"unchanged output")
        result = self.run_merge()
        self.assertEqual(result.returncode, 1)
        self.assertIn(message, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(len(result.stderr.splitlines()), 1)
        self.assertEqual(self.existing.read_bytes(), source)
        self.assertEqual(self.output.read_bytes(), b"unchanged output")

    def test_empty_object(self):
        self.assert_merge("{}", {"enabled": True}, {"enabled": True})

    def test_preserves_unconfigured_values(self):
        self.assert_merge(
            '{"keep": 1, "replace": 2}', {"replace": 3}, {"keep": 1, "replace": 3}
        )

    def test_recursively_merges_objects(self):
        self.assert_merge(
            '{"nested": {"deeper": {"keep": true, "replace": 1}}}',
            {"nested": {"deeper": {"replace": 2, "new": False}}},
            {"nested": {"deeper": {"keep": True, "replace": 2, "new": False}}},
        )

    def test_replaces_arrays(self):
        self.assert_merge(
            '{"items": [1, 2], "nested": {"items": [3]}}',
            {"items": [], "nested": {"items": [4]}},
            {"items": [], "nested": {"items": [4]}},
        )

    def test_replaces_values_of_different_types(self):
        self.assert_merge(
            '{"object": {"a": 1}, "scalar": 2, "array": [1]}',
            {"object": None, "scalar": {"a": 3}, "array": False},
            {"object": None, "scalar": {"a": 3}, "array": False},
        )

    def test_empty_configuration_preserves_values(self):
        self.assert_merge('{"nested": {"keep": true}}', {}, {"nested": {"keep": True}})

    def test_line_comments_and_crlf(self):
        self.assert_merge(
            '{\r\n// comment\r\n"keep": 1 // trailing\r\n}// eof', {}, {"keep": 1}
        )

    def test_block_comments(self):
        self.assert_merge(
            '/* before */{"keep"/* multiline\ncomment */: 1}/* end */', {}, {"keep": 1}
        )

    def test_trailing_commas_in_objects_and_arrays(self):
        self.assert_merge(
            '{"items": [1, 2, ], "nested": {"keep": true,},}',
            {},
            {"items": [1, 2], "nested": {"keep": True}},
        )

    def test_preserves_comment_markers_and_escapes_in_strings(self):
        values = {
            "url": "https://example.com//path",
            "block": "/* text */",
            "escaped": 'quote " and slash \\ // /* ,} ,]',
        }
        self.assert_merge(json.dumps(values), {}, values)

    def test_utf8_bom_and_unicode(self):
        self.assert_merge(
            '\ufeff{"label": "café 日本語"}', {}, {"label": "café 日本語"}
        )

    def test_rejects_invalid_json(self):
        for source in [
            b"",
            b"// only a comment",
            b'{"bad":}',
            b'{"text": "unterminated}',
            b'{"a": 1} trailing',
        ]:
            with self.subTest(source=source):
                self.assert_rejected(
                    source, "Cannot parse the existing IDE settings file:"
                )

    def test_rejects_unterminated_block_comment(self):
        self.assert_rejected(
            b'{"keep": 1} /* unfinished', "unterminated block comment in IDE settings"
        )

    def test_comments_do_not_join_separate_tokens(self):
        self.assert_rejected(
            b'{"number": 1/* comment */2}',
            "Cannot parse the existing IDE settings file:",
        )

    def test_rejects_non_object_roots(self):
        for source in [b"[]", b"[1, 2]", b"null", b"false", b"42", b'"text"']:
            with self.subTest(source=source):
                self.assert_rejected(source, "must contain a JSON object")

    def test_rejects_invalid_utf8(self):
        self.assert_rejected(
            b'{"text": "\xff"}', "Cannot parse the existing IDE settings file:"
        )

    def test_reports_missing_file(self):
        result = self.run_merge()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Cannot parse the existing IDE settings file:", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
