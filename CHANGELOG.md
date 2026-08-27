# Changelog

All notable changes to this project will be documented here.

## [2.1.2] - 2026-08-27

- Forced every plugin-owned QML `Text` item to render as plain text.
- Kept controller-derived group and proxy names out of the shared `PanelHero`,
  whose internal labels use automatic rich-text detection.
- Added regression coverage for controller-supplied markup-like strings.

## [2.1.1] - 2026-08-26

- Blocked controller API redirects so Bearer credentials cannot cross origins.
- Added a 16 MiB streamed limit for controller responses.
- Hardened configuration and secret reads against symlinks, non-regular files,
  unsafe permissions, hard links, and oversized content.
- Added regression tests for the security hardening.

## [2.1.0] - 2026-08-26

- Added first-run setup for the controller URL, dashboard URL, and secret.
- Added Rule, Global, and Direct mode controls.
- Added proxy latency display and latency colors.
- Added optional lowest-latency sorting.
- Hid proxies that the controller reports as unreachable.
- Added active-server latency to each proxy group.
- Added dashboard-name detection for common Mihomo dashboards.
- Added graceful offline handling for private LAN, VPN, and Tailnet setups.

[2.1.2]: https://github.com/cbayschm74/omarchy-openclash/releases/tag/v2.1.2
[2.1.1]: https://github.com/cbayschm74/omarchy-openclash/releases/tag/v2.1.1
[2.1.0]: https://github.com/cbayschm74/omarchy-openclash/releases/tag/v2.1.0
