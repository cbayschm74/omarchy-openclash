#!/usr/bin/env python3
"""Small, dependency-free Mihomo/OpenClash API client for the bar plugin."""

import json
import os
import stat
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request


GROUP_TYPES = {"Selector", "URLTest", "Fallback", "LoadBalance"}
API_RESPONSE_LIMIT = 16 * 1024 * 1024
CONFIG_FILE_LIMIT = 64 * 1024
SECRET_FILE_LIMIT = 8 * 1024
READ_CHUNK_SIZE = 64 * 1024


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Reject redirects so controller credentials never cross origins."""

    def http_error_302(self, req, fp, code, msg, headers):
        fp.close()
        raise urllib.error.HTTPError(
            req.full_url,
            code,
            "Controller redirects are disabled",
            headers,
            fp,
        )

    http_error_301 = http_error_302
    http_error_303 = http_error_302
    http_error_307 = http_error_302
    http_error_308 = http_error_302


HTTP_OPENER = urllib.request.build_opener(NoRedirectHandler())


def fail(message, code=1):
    print(json.dumps({"ok": False, "error": str(message)}, ensure_ascii=False))
    raise SystemExit(code)


def read_bounded_response(response, limit=API_RESPONSE_LIMIT):
    """Read a response incrementally without ever retaining more than limit."""
    content_length = response.headers.get("Content-Length")
    if content_length is not None:
        try:
            announced = int(content_length)
        except (TypeError, ValueError):
            announced = -1
        if announced > limit:
            raise ValueError("Controller response exceeds the 16 MiB limit")

    chunks = []
    total = 0
    while True:
        remaining = limit - total
        chunk = response.read(min(READ_CHUNK_SIZE, remaining + 1))
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            raise ValueError("Controller response exceeds the 16 MiB limit")
        chunks.append(chunk)
    return b"".join(chunks)


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
    with HTTP_OPENER.open(req, timeout=12) as response:
        raw = read_bounded_response(response)
        return json.loads(raw.decode("utf-8")) if raw else {}


def normalize_url(value, label, required=True):
    text = str(value or "").strip()
    if not text and not required:
        return ""
    parsed = urllib.parse.urlparse(text)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc or not parsed.hostname:
        fail(label + " must start with http:// or https:// and include a host")
    try:
        parsed.port
    except ValueError:
        fail(label + " contains an invalid port")
    if parsed.username is not None or parsed.password is not None:
        fail(label + " must not contain embedded credentials")
    if parsed.query or parsed.fragment:
        fail(label + " must not contain a query string or fragment")
    return text.rstrip("/")


def read_private_text(path, label, limit, required=True):
    """Read a small owner-only regular file without following path symlinks."""
    target = os.path.expanduser(path)
    flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK | os.O_NOFOLLOW
    try:
        fd = os.open(target, flags)
    except FileNotFoundError:
        if not required:
            return None
        fail("Cannot read " + label + ": file does not exist")
    except OSError as exc:
        fail("Cannot securely read " + label + ": " + str(exc))

    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            fail(label + " must be a regular file")
        if metadata.st_uid != os.getuid():
            fail(label + " must be owned by the current user")
        if metadata.st_nlink != 1:
            fail(label + " must not have multiple hard links")
        if metadata.st_mode & 0o077:
            fail(label + " permissions must be 0600")
        if metadata.st_size > limit:
            fail(label + " exceeds its size limit")

        chunks = []
        total = 0
        while True:
            remaining = limit - total
            chunk = os.read(fd, min(READ_CHUNK_SIZE, remaining + 1))
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                fail(label + " exceeds its size limit")
            chunks.append(chunk)
        try:
            return b"".join(chunks).decode("utf-8")
        except UnicodeDecodeError:
            fail(label + " is not valid UTF-8")
    finally:
        os.close(fd)


def read_secret(path, required=True):
    text = read_private_text(path, "controller secret", SECRET_FILE_LIMIT, required)
    secret = "" if text is None else text.strip()
    if required and not secret:
        fail("Controller secret is empty")
    return secret


def read_config(path, required=True):
    text = read_private_text(path, "OpenClash configuration", CONFIG_FILE_LIMIT, required)
    if text is None:
        return None
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        fail("Cannot read OpenClash setup: " + str(exc))
    if not isinstance(data, dict):
        fail("OpenClash configuration must contain a JSON object")
    return {
        "apiBase": normalize_url(data.get("apiBase", ""), "Controller URL"),
        "dashboardUrl": normalize_url(data.get("dashboardUrl", ""), "Dashboard URL", required=False),
    }


def ensure_private_directory(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    flags = os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW
    try:
        fd = os.open(path, flags)
    except OSError as exc:
        fail("Cannot securely open the OpenClash configuration directory: " + str(exc))
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid():
            fail("OpenClash configuration directory must be an owner-controlled directory")
        os.fchmod(fd, 0o700)
    finally:
        os.close(fd)


def write_private(path, text):
    target = os.path.expanduser(path)
    parent = os.path.dirname(target)
    ensure_private_directory(parent)
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
    except (TimeoutError, ValueError, UnicodeDecodeError) as exc:
        fail("Invalid controller response: " + str(exc))


if __name__ == "__main__":
    main()
