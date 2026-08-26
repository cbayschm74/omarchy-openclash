# Contributing

Bug reports and focused pull requests are welcome.

## Before opening an issue

1. Update to the latest plugin and Omarchy versions.
2. Confirm that the controller works through its own dashboard.
3. Search existing issues for the same behavior.
4. Remove controller secrets, private hostnames, proxy names, and Tailnet or
   LAN details from logs and screenshots.

Include the plugin version from `manifest.json`, the Omarchy version, steps to
reproduce, expected behavior, and the exact non-sensitive error shown by the
widget.

## Development workflow

Fork and clone the repository, then validate it on an Omarchy system:

```bash
omarchy plugin validate .
python3 -m unittest discover -s tests -v
```

Keep changes narrowly scoped. The helper must remain dependency-free, secrets
must not appear in process arguments or logs, and configuration changes must
stay under `~/.config/omarchy/openclash/`.

For local testing, install the checkout with `omarchy plugin add "$PWD"
--enable`. Do not commit local connection settings, secrets, captures that
show private proxy names, or generated Python cache files.

By submitting a contribution, you agree that it may be distributed under the
project's MIT license.
