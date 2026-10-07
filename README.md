# Brain Bridge — Open-source local MCP tunnel launcher

[راهنمای فارسی](docs/README.fa.md) · [Architecture](docs/ARCHITECTURE.md) · [Security](SECURITY.md) · [Roadmap](docs/ROADMAP.md)

**Status: v0.1.0 community prototype — Windows only, not an Obsidian Community Plugin.**

Brain Bridge is a small **local setup and launcher** for connecting an existing [Obsidian MCP Connector](https://github.com/istefox/obsidian-mcp-connector) endpoint to ChatGPT via the official [OpenAI tunnel-client](https://github.com/openai/tunnel-client). It does **not** duplicate or modify those projects, and does not include or expose any Obsidian vault content.

### What it does now

- Interactive Windows PowerShell 5.1 setup — enter your own existing tunnel ID and Obsidian MCP URL.
- Stores your OpenAI Runtime API key and the Obsidian MCP token using **Windows DPAPI** for the current Windows user.
- Adds an optional **hidden, per-user startup shortcut** (no administrator permissions needed).
- Waits for Obsidian's local MCP server to become available and validates its token before starting the tunnel.
- Validates the Runtime API key with OpenAI at startup and stops rather than retrying indefinitely on unauthorized credentials.
- Offers status, stop and uninstall helper scripts. Uses only PowerShell and Windows built-in tools.
- Does not bundle OpenAI executables or collect telemetry.

### Requirements

1. Windows 10/11 desktop and PowerShell 5.1+.
2. Obsidian with the existing [MCP Connector](https://github.com/istefox/obsidian-mcp-connector) enabled, and a token created in **Settings → MCP Connector → Access Control**.
3. The official `tunnel-client.exe` downloaded and extracted from [openai/tunnel-client releases](https://github.com/openai/tunnel-client/releases). Check published `SHA256SUMS.txt` before running downloaded executables.
4. An OpenAI Platform **Tunnel ID** and a Restricted Runtime API key with **Tunnels Read + Use** permission. See [the official documentation](https://github.com/openai/tunnel-client/blob/master/docs/end-user-guide.md).
5. A ChatGPT workspace with access to create a custom MCP plugin.

### Install

1. Download this source and extract it **outside your vault**.
2. Open PowerShell in the project directory, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-BrainBridge.ps1 -EnableAutoStart
```

3. Enter the path of the official `tunnel-client.exe`, Tunnel ID, **direct Obsidian MCP URL** such as `http://127.0.0.1:27200/mcp` (NOT the Codex broker URL), OpenAI runtime key, and raw Obsidian token. **Do not paste secrets into chats or source files.**
4. Check status:

```powershell
& "$env:LOCALAPPDATA\BrainBridge\Status-BrainBridge.ps1" -CheckOpenAI
```

5. Launch without reboot:

```powershell
Start-Process wscript.exe -ArgumentList ('"' + $env:LOCALAPPDATA + '\BrainBridge\Run-Hidden.vbs"')
```

6. Confirm healthy status. In ChatGPT Plugins, create a **custom MCP server** using the same Tunnel ID. Only select **No authentication** there when the vault token is inserted by the local runner.

### Configuration & location

Installed files live in `%LOCALAPPDATA%\BrainBridge`. `config.json` contains no secrets; `.dpapi` files are encrypted for the current Windows user. A Windows Startup shortcut launches the tunnel hidden. The connection requires the PC, the user session, and the Obsidian MCP server to be running.

### Useful commands

```powershell
& "$env:LOCALAPPDATA\BrainBridge\Status-BrainBridge.ps1" -CheckOpenAI
& "$env:LOCALAPPDATA\BrainBridge\Stop-BrainBridge.ps1"
& "$env:LOCALAPPDATA\BrainBridge\Remove-BrainBridge.ps1"
```

### Security

Vaults may contain sensitive content. For initial use, restrict exposed tools to **Read/Search** and keep shell/command execution disabled. The Tunnel provides remote access to the selected MCP capability surface. See [SECURITY.md](SECURITY.md).

### Not implemented yet

- One-click Obsidian Community Plugin UI.
- Multi-vault federation, common memory, or cross-agent chat-history sync.
- macOS/Linux support, automatic download of third-party executables, or automatic creation of OpenAI Platform resources.
- Formal security audit or Windows end-to-end testing on independent computers.

### License and attribution

MIT licensed — [LICENSE](LICENSE). Other projects retain their own licenses and trademarks. Not affiliated with OpenAI or Obsidian.
