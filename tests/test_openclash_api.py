import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "openclash_api.py"
SPEC = importlib.util.spec_from_file_location("openclash_api", MODULE_PATH)
API = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(API)


class FakeResponse(io.BytesIO):
    def __init__(self, payload, content_length=None):
        super().__init__(payload)
        self.headers = {}
        if content_length is not None:
            self.headers["Content-Length"] = str(content_length)


def assert_rejected(testcase, action):
    with redirect_stdout(io.StringIO()):
        with testcase.assertRaises(SystemExit):
            action()


class DelayTests(unittest.TestCase):
    def test_latest_delay_uses_newest_successful_measurement(self):
        proxy = {"history": [{"delay": 40}, {"delay": 0}, {"delay": 75}]}
        self.assertEqual(API.latest_delay(proxy), 75)

    def test_latest_delay_ignores_failed_measurements(self):
        proxy = {"history": [{"delay": 80}, {"delay": 0}]}
        self.assertEqual(API.latest_delay(proxy), 80)

    def test_resolved_delay_follows_nested_selector(self):
        health = {"server-a": {"alive": True, "delay": 123}}
        proxies = {
            "group-a": {"now": "group-b"},
            "group-b": {"now": "server-a"},
        }
        self.assertEqual(API.resolved_delay("group-a", health, proxies), 123)

    def test_resolved_delay_stops_on_cycles(self):
        proxies = {"group-a": {"now": "group-b"}, "group-b": {"now": "group-a"}}
        self.assertEqual(API.resolved_delay("group-a", {}, proxies), 0)


class HealthTests(unittest.TestCase):
    def test_reachable_duplicate_wins(self):
        health = {}
        API.record_health(health, "server-a", {"alive": False, "history": []})
        API.record_health(health, "server-a", {"alive": True, "history": [{"delay": 210}]})
        self.assertEqual(health["server-a"], {"alive": True, "delay": 210})

    def test_best_successful_duplicate_delay_wins(self):
        health = {}
        API.record_health(health, "server-a", {"alive": True, "history": [{"delay": 210}]})
        API.record_health(health, "server-a", {"alive": True, "history": [{"delay": 95}]})
        self.assertEqual(health["server-a"], {"alive": True, "delay": 95})


class NetworkSecurityTests(unittest.TestCase):
    def test_redirect_handler_rejects_every_redirect(self):
        request = API.urllib.request.Request("https://controller.example/proxies")
        for code in (301, 302, 303, 307, 308):
            response = FakeResponse(b"")
            headers = {"Location": "https://attacker.example/capture"}
            handler = API.NoRedirectHandler()
            callback = getattr(handler, "http_error_" + str(code))
            with self.assertRaises(API.urllib.error.HTTPError) as raised:
                callback(request, response, code, "Redirect", headers)
            raised.exception.close()
            self.assertTrue(response.closed)

    def test_bounded_response_rejects_announced_oversize_body(self):
        response = FakeResponse(b"{}", content_length=65)
        with self.assertRaises(ValueError):
            API.read_bounded_response(response, limit=64)

    def test_bounded_response_rejects_streamed_oversize_body(self):
        response = FakeResponse(b"x" * 65)
        with self.assertRaises(ValueError):
            API.read_bounded_response(response, limit=64)

    def test_request_uses_redirect_blocking_opener(self):
        response = FakeResponse(b'{"ok": true}')
        with mock.patch.object(API.HTTP_OPENER, "open", return_value=response) as opened:
            result = API.request("https://controller.example", "secret", "/version")
        self.assertEqual(result, {"ok": True})
        opened.assert_called_once()


class LocalFileSecurityTests(unittest.TestCase):
    def write_private_file(self, path, payload):
        path.write_text(payload, encoding="utf-8")
        path.chmod(0o600)

    def test_valid_private_config_and_secret_are_read(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            config = root / "config.json"
            secret = root / "secret"
            self.write_private_file(config, json.dumps({
                "apiBase": "https://controller.example",
                "dashboardUrl": "https://controller.example/ui/",
            }))
            self.write_private_file(secret, "correct horse battery staple\n")
            self.assertEqual(API.read_config(config)["apiBase"], "https://controller.example")
            self.assertEqual(API.read_secret(secret), "correct horse battery staple")

    def test_symlink_is_rejected_even_when_optional(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            target = root / "real-secret"
            link = root / "secret"
            self.write_private_file(target, "secret")
            link.symlink_to(target)
            assert_rejected(self, lambda: API.read_secret(link, required=False))

    def test_non_regular_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary) / "secret"
            directory.mkdir()
            assert_rejected(self, lambda: API.read_secret(directory))

    def test_group_readable_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            secret = pathlib.Path(temporary) / "secret"
            self.write_private_file(secret, "secret")
            secret.chmod(0o640)
            assert_rejected(self, lambda: API.read_secret(secret))

    def test_oversized_secret_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            secret = pathlib.Path(temporary) / "secret"
            self.write_private_file(secret, "x" * (API.SECRET_FILE_LIMIT + 1))
            assert_rejected(self, lambda: API.read_secret(secret))

    def test_oversized_config_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            config = pathlib.Path(temporary) / "config.json"
            self.write_private_file(config, "x" * (API.CONFIG_FILE_LIMIT + 1))
            assert_rejected(self, lambda: API.read_config(config))


if __name__ == "__main__":
    unittest.main()
