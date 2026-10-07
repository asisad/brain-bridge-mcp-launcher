# Security policy — Brain Bridge v0.2 prototype

Brain Bridge is a local Windows wrapper around the existing Obsidian MCP Connector and official OpenAI tunnel-client. It is **not** a vault sandbox, a secure multiparty gateway, or an authentication replacement.

## Secrets and privacy

- Enter credentials through WPF PasswordBox controls or masked `Read-Host -AsSecureString`. Never put tokens in source files, screenshots, command-line arguments, logs, or Git commits.
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
- The runner checks Runtime tunnel lookup and client configuration before starting; it makes at most six attempts, including authorization failures. Read + Use is required, but only runtime operation can demonstrate Use access.
- Raw client stdout/stderr is discarded. New state messages are fixed strings. Legacy v0.1 logs are not sanitized retroactively and must never be published without review.
- Credentials are passed only in the child process environment, never command-line arguments. DPAPI protects storage, not same-user/admin process inspection or managed-memory copies. Directory ACL inheritance is disabled, granting the current user and SYSTEM access.
- Only direct loopback `/mcp` URLs without credentials, queries or fragments are accepted; installer MCP checks do not follow redirects. Initialize does not certify the server is Obsidian or enumerate granted tool scopes. Review access inside Obsidian.
- Verify the official release checksum before selecting the executable. A saved SHA-256 detects later changes; it is not a publisher signature or automatic provenance verification.
- Deletion requires a local directory named BrainBridge, an ownership marker and no reparse points. Stop verifies process name, full script argument and creation time before stopping its tree. A same-user attacker can alter code/state; this is not a sandbox.
- Updates are not transactional. Config and encrypted credentials are backed up, but a disk/write failure may require re-running setup. Stop old versions before upgrading.

## Reporting

Share sanitized reproduction steps through GitHub issues; **do not** post secrets, raw Vault exports, encrypted credential blobs, or unredacted logs. Use private security reporting when available.
