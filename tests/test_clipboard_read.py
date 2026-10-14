import importlib.util
import pathlib
import sys
import time
import unittest

spec = importlib.util.spec_from_file_location("clipboard_read", pathlib.Path(__file__).parents[1] / "clipboard_read.py")
clipboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clipboard)


class ClipboardBoundTests(unittest.TestCase):
    def read(self, script, **kwargs):
        return clipboard.read_clipboard((sys.executable, "-c", script), **kwargs)

    def test_single_line_and_exact_byte_limit(self):
        self.assertEqual(self.read("print('x'*64, end='')", limit=64), "x" * 64)

    def test_streaming_oversize_is_rejected_without_buffering_the_provider(self):
        start = time.monotonic()
        with self.assertRaisesRegex(ValueError, "exceeds"):
            self.read("import os,time; os.write(1,b'x'*65); time.sleep(10)", limit=64, timeout=0.5)
        self.assertLess(time.monotonic() - start, 1)

    def test_trickle_provider_obeys_total_deadline_not_per_chunk_timeout(self):
        start = time.monotonic()
        with self.assertRaisesRegex(ValueError, "timed out"):
            self.read("import os,time\nfor i in range(100):\n os.write(1,b'x'); time.sleep(0.03)", timeout=0.2)
        self.assertLess(time.monotonic() - start, 0.8)

    def test_eof_does_not_bypass_process_deadline(self):
        with self.assertRaisesRegex(ValueError, "timed out"):
            self.read("import os,time; os.close(1); time.sleep(10)", timeout=0.2)

    def test_utf8_multibyte_counts_toward_byte_budget(self):
        with self.assertRaisesRegex(ValueError, "exceeds"):
            self.read("import os; os.write(1, ('é'*33).encode())", limit=64)

    def test_invalid_utf8_and_control_characters_are_rejected(self):
        for raw in (b"\xff", b"url\nsecret", b"a\x00b", b"a\tb"):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                self.read("import os; os.write(1," + repr(raw) + ")")

    def test_failed_provider_and_missing_command_do_not_leak_text(self):
        with self.assertRaisesRegex(ValueError, "unavailable"):
            self.read("print('private-data',end=''); raise SystemExit(1)")
        with self.assertRaises(OSError):
            clipboard.read_clipboard(("/missing-openclash-clipboard-provider",))
