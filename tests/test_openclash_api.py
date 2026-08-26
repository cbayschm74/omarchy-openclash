import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "openclash_api.py"
SPEC = importlib.util.spec_from_file_location("openclash_api", MODULE_PATH)
API = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(API)


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


if __name__ == "__main__":
    unittest.main()
