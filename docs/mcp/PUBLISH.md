---
title: "Publishing Metadata"
created: 2026-05-13
updated: 2026-07-30
---

# Publishing Metadata

Registry and package metadata must agree:

| Surface | Value |
|---|---|
| `server.json.name` | `ai.dinglebear/rtailscale` |
| npm `mcpName` | `ai.dinglebear/rtailscale` |
| package name | `tailscale-rmcp` |
| binary alias | `rtailscale` |
| remote URL | `https://ts.example.internal/mcp` |

Validate:

```bash
mcp-publisher validate server.json
npm --prefix packages/tailscale-rmcp run check
npm pack --prefix packages/tailscale-rmcp --dry-run --json
```

The npm package downloads release assets from GitHub Releases during
postinstall. Keep `binaryVersion`, package `version`, and release assets in
sync.
