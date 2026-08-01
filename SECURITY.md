# Security policy

Report vulnerabilities privately through GitHub Security Advisories for
`dinglebear-ai/rtailscale`.

High-impact findings include:

- exposure of Tailscale API, OAuth, auth-key, or bearer credentials;
- an authentication or scope-check bypass on the MCP HTTP surface;
- device deletion or another destructive operation that bypasses confirmation;
- command, URL, header, tailnet, device-ID, or request-body injection;
- divergence that lets the CLI or MCP shim bypass `TailscaleService` policy;
- release, installer, npm, plugin, or registry publication of unverified bytes.

Do not open a public issue containing live credentials or a working
credential-exfiltration, authorization-bypass, or publication-bypass proof.
