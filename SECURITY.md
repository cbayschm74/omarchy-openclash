# Security policy

## Supported versions

Security fixes are applied to the latest released version of the plugin.
Users should update with:

```bash
omarchy plugin update cbayschm.openclash
```

## Reporting a vulnerability

Please do not publish controller secrets, private hostnames, proxy names, or
other sensitive configuration in a public issue.

Report a suspected vulnerability through GitHub's private vulnerability
reporting feature for this repository. If that feature is unavailable, open a
minimal issue asking the maintainer for a private contact method without
including exploit details or credentials.

Include the plugin version, Omarchy version, expected behavior, and the
smallest reproduction that does not expose private data. Never send a real
controller secret; use a clearly fake placeholder.

## Security model

Omarchy plugins execute as the logged-in user inside the long-running shell
and are not sandboxed. This plugin starts a local Python helper and sends
authenticated requests only to the controller URL entered by the user. It
does not install packages, use `sudo`, modify network configuration, or send
telemetry.

The helper rejects controller redirects, streams API responses under a 16 MiB
limit, and reads setup files through no-follow descriptors. Configuration and
secret files must be owner-only regular files within their documented size
limits.
