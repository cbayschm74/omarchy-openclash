#!/usr/bin/env python3
"""Small, dependency-free Mihomo/OpenClash API client for the bar plugin."""

import json
import os
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request


GROUP_TYPES = {"Selector", "URLTest", "Fallback", "LoadBalance"}


def fail(message, code=1):
    print(json.dumps({"ok": False, "error": str(message)}, ensure_ascii=False))
    raise SystemExit(code)


def request(base, secret, path, method="GET", body=None):
    url = base.rstrip("/") + path
    headers = {
        "Authorization": "Bearer " + secret,
        "Accept": "application/json",
    }
    data = None
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=12) as response:
        raw = response.read()
        return json.loads(raw.decode("utf-8")) if raw else {}


def normalize_url(value, label, required=True):
    text = str(value or "").strip()
    if not text and not required:
        return ""
    parsed = urllib.parse.urlparse(text)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        fail(label + " must start with http:// or https:// and include a host")
    return text.rstrip("/")


def read_secret(path, required=True):
    try:
        with open(os.path.expanduser(path), "r", encoding="utf-8") as handle:
            secret = handle.read().strip()
    except OSError as exc:
        if not required:
            return ""
        fail("Cannot read controller secret: " + str(exc))
    if required and not secret:
        fail("Controller secret is empty")
    return secret


def read_config(path, required=True):
    try:
        with open(os.path.expanduser(path), "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        if not required:
            return None
        fail("Cannot read OpenClash setup: " + str(exc))
    return {
        "apiBase": normalize_url(data.get("apiBase", ""), "Controller URL"),
        "dashboardUrl": normalize_url(data.get("dashboardUrl", ""), "Dashboard URL", required=False),
    }


def write_private(path, text):
    target = os.path.expanduser(path)
    parent = os.path.dirname(target)
    os.makedirs(parent, mode=0o700, exist_ok=True)
    os.chmod(parent, 0o700)
    fd, temporary = tempfile.mkstemp(prefix=".openclash-", dir=parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, target)
        os.chmod(target, 0o600)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def runtime_credentials(config_path, secret_path):
    config = read_config(config_path)
    return config, read_secret(secret_path)


def latest_delay(proxy):
    """Return the newest successful delay measurement, or zero if unknown."""
    history = proxy.get("history") or []
    for measurement in reversed(history):
        delay = measurement.get("delay", 0)
        if isinstance(delay, (int, float)) and delay > 0:
            return int(delay)
    return 0


def record_health(health, name, proxy):
    """Merge duplicate provider entries, preferring a reachable measurement."""
    alive = proxy.get("alive")
    if alive is not True and alive is not False:
        return
    candidate = {"alive": alive, "delay": latest_delay(proxy)}
    current = health.get(name)
    if current is None or (candidate["alive"] and not current["alive"]):
        health[name] = candidate
    elif candidate["alive"] == current["alive"] and candidate["delay"] > 0:
        if current["delay"] <= 0 or candidate["delay"] < current["delay"]:
            health[name] = candidate


def resolved_delay(name, health, proxies, seen=None):
    """Follow nested selector choices until a measured proxy is reached."""
    state = health.get(name)
    if state is not None and state["delay"] > 0:
        return state["delay"]
    visited = set() if seen is None else seen
    if not name or name in visited:
        return 0
    visited.add(name)
    nested = proxies.get(name) or {}
    selected = nested.get("now", "")
    return resolved_delay(selected, health, proxies, visited) if selected else 0


def main():
    if len(sys.argv) < 4:
        fail("usage: openclash_api.py ACTION CONFIG_FILE SECRET_FILE [ARGS]")

    action, config_file, secret_file = sys.argv[1:4]
    try:
        if action == "setup-state":
            config = read_config(config_file, required=False)
            has_secret = bool(read_secret(secret_file, required=False))
            configured = config is not None and has_secret
            print(json.dumps({
                "ok": True,
                "configured": configured,
                "apiBase": config["apiBase"] if config else "",
                "dashboardUrl": config["dashboardUrl"] if config else "",
            }, ensure_ascii=False))
        elif action == "configure":
            try:
                setup = json.loads(sys.stdin.readline())
            except json.JSONDecodeError:
                fail("Invalid setup data")
            base = normalize_url(setup.get("apiBase", ""), "Controller URL")
            dashboard = normalize_url(setup.get("dashboardUrl", ""), "Dashboard URL", required=False)
            if not dashboard:
                dashboard = base + "/ui/"
            secret = str(setup.get("secret", "")).strip() or read_secret(secret_file, required=False)
            if not secret:
                fail("Controller secret is required for initial setup")

            # Do not persist unverified credentials. Both endpoints are used by
            # the widget and together catch a dashboard URL accidentally entered
            # in place of the external-controller URL.
            request(base, secret, "/version")
            request(base, secret, "/proxies")

            write_private(config_file, json.dumps({
                "apiBase": base,
                "dashboardUrl": dashboard,
            }, ensure_ascii=False, indent=2) + "\n")
            write_private(secret_file, secret)
            print(json.dumps({
                "ok": True,
                "configured": True,
                "apiBase": base,
                "dashboardUrl": dashboard,
            }, ensure_ascii=False))
        elif action == "status":
            config, secret = runtime_credentials(config_file, secret_file)
            base = config["apiBase"]
            payload = request(base, secret, "/proxies")
            providers = request(base, secret, "/providers/proxies")
            config = request(base, secret, "/configs")
            health = {}

            # Provider entries contain the real leaf-server health. Top-level
            # proxies add special choices and nested groups such as DIRECT and
            # the regional gateways.
            for provider in providers.get("providers", {}).values():
                for proxy in provider.get("proxies") or []:
                    record_health(health, proxy.get("name", ""), proxy)
            for name, proxy in payload.get("proxies", {}).items():
                if name not in health:
                    record_health(health, name, proxy)

            groups = []
            top_proxies = payload.get("proxies", {})
            for name, proxy in top_proxies.items():
                if proxy.get("type") not in GROUP_TYPES or not proxy.get("all"):
                    continue
                current_name = proxy.get("now", "")
                candidates = []
                hidden = 0
                for candidate_name in proxy.get("all", []):
                    state = health.get(candidate_name)
                    if state is not None and state["alive"] is False:
                        hidden += 1
                        continue
                    candidates.append({
                        "name": candidate_name,
                        "delay": resolved_delay(candidate_name, health, top_proxies),
                    })
                groups.append({
                    "name": name,
                    "type": proxy.get("type", ""),
                    "now": current_name,
                    "nowDelay": resolved_delay(current_name, health, top_proxies),
                    "all": candidates,
                    "total": len(proxy.get("all", [])),
                    "hidden": hidden,
                })
            groups.sort(key=lambda item: (item["name"] != "GLOBAL", item["name"].casefold()))
            print(json.dumps({
                "ok": True,
                "mode": str(config.get("mode", "rule")).lower(),
                "groups": groups,
            }, ensure_ascii=False))
        elif action == "set":
            if len(sys.argv) != 6:
                fail("set requires a group and server")
            config, secret = runtime_credentials(config_file, secret_file)
            base = config["apiBase"]
            group, server = sys.argv[4:6]
            path = "/proxies/" + urllib.parse.quote(group, safe="")
            request(base, secret, path, method="PUT", body={"name": server})
            print(json.dumps({"ok": True, "group": group, "server": server}, ensure_ascii=False))
        elif action == "mode":
            if len(sys.argv) != 5:
                fail("mode requires rule, global, or direct")
            config, secret = runtime_credentials(config_file, secret_file)
            base = config["apiBase"]
            mode = sys.argv[4].lower()
            if mode not in {"rule", "global", "direct"}:
                fail("Unsupported mode: " + mode)
            request(base, secret, "/configs", method="PATCH", body={"mode": mode})
            print(json.dumps({"ok": True, "mode": mode}, ensure_ascii=False))
        else:
            fail("Unknown action: " + action)
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            fail("Controller rejected the saved secret (401)")
        fail("Controller returned HTTP " + str(exc.code))
    except urllib.error.URLError as exc:
        fail("Cannot reach OpenClash: " + str(exc.reason))
    except (TimeoutError, json.JSONDecodeError) as exc:
        fail("Invalid controller response: " + str(exc))


if __name__ == "__main__":
    main()
