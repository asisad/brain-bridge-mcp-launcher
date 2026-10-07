# Architecture — v0.1

```text
ChatGPT custom MCP plugin
          |
   OpenAI control plane
          |
   Official tunnel-client.exe  <-- Runtime key, loaded from DPAPI
          |
   127.0.0.1:<port>/mcp        <-- Obsidian token, loaded from DPAPI
          |
   Existing Obsidian MCP Connector
          |
   Locally opened Obsidian Vault
```

## Design choices

1. Do not duplicate the Obsidian MCP server or OpenAI tunnel implementation.
2. Support a single Tunnel to a single direct local MCP URL in v0.1.
3. Separate the OpenAI Runtime key from the Obsidian bearer token.
4. Save both secrets encrypted for the current Windows user, outside any Vault.
5. Use a hidden user-level Startup shortcut, no administrator rights.
6. Validate OpenAI permissions and local MCP authentication before launching.
7. Wait for Obsidian when offline and supervise tunnel-client after exit.

## Failure modes

- **Control plane 401:** wrong/revoked/scope-limited OpenAI Runtime key.
- **Local MCP 401:** wrong Obsidian token, endpoint, or Vault configuration.
- **/readyz HTTP 200:** a listener exists; verify its response contents and tool access.
- **Duplicate runner:** guarded by a named Windows mutex; externally started clients need manual coordination.

This project does not sync notes, run shell commands against vaults, or create a shared multi-vault memory layer.
