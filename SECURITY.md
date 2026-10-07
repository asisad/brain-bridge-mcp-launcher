# Security policy — Brain Bridge v0.1

Brain Bridge is a local Windows wrapper around the existing Obsidian MCP Connector and official OpenAI tunnel-client. It is **not** a vault sandbox, a secure multiparty gateway, or an authentication replacement.

## Secrets and privacy

- Enter credentials only via masked `Read-Host -AsSecureString`. Never put tokens in source files, screenshots, command-line arguments, logs, or Git commits.
- The installer stores two encrypted `.dpapi` files, protected for the **current Windows account**. DPAPI does not defend against malicious software running as that user.
- `config.json` stores local paths, a Tunnel ID and a local MCP URL; it has **no credentials**. Do not publish local installation directories.
- The OpenAI Runtime key should have the least permissions required: **Tunnels Read + Use**.
- Use a different Obsidian access token for each installation/client when possible, with minimum MCP tool scope.

## What a tunnel exposes

- A remotely connected AI can invoke MCP tools authorized by the vault token. If write/delete or execution tools are authorized, their risks are higher.
- A locally hosted MCP server is **not the same as completely local AI inference**; tool responses can reach the selected model provider.
- Imported notes, web content and tool descriptions should be treated as untrusted instructions.
- Do not share another person's token or reuse the original developer's credentials.
- Start with read-only permissions. Avoid shell execution and unrestricted filesystem access.

## Prototype limitations

- This version has not been independently audited or end-to-end tested on Windows machines beyond its originating setup context.
- The startup mechanism is a per-user Startup shortcut, not a Windows Service.
- The local MCP endpoint must remain on its configured port.
- The runner validates OpenAI access before starting, and stops on failed authorization rather than endlessly retrying.
- Operational logs may contain local URLs or other identifying metadata; redact them before filing issues.

## Reporting

Share sanitized reproduction steps through GitHub issues; **do not** post secrets, raw Vault exports, encrypted credential blobs, or unredacted logs. Use private security reporting when available.
