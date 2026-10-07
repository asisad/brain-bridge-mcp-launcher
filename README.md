# Brain Bridge — Open-source local MCP tunnel launcher

[راهنمای فارسی](docs/README.fa.md) · [Architecture](docs/ARCHITECTURE.md) · [Security](SECURITY.md) · [Roadmap](docs/ROADMAP.md)

**Status: v0.2.0 community prototype — Windows only, unsigned, not an Obsidian Community Plugin.** See the [Persian PDR and validation boundaries](docs/PDR.fa.md).

Brain Bridge is a small **local setup and launcher** for connecting an existing [Obsidian MCP Connector](https://github.com/istefox/obsidian-mcp-connector) endpoint to ChatGPT via the official [OpenAI tunnel-client](https://github.com/openai/tunnel-client). It does **not** duplicate or modify those projects, and does not include or expose any Obsidian vault content.

### What it does now

- Double-click graphical WPF setup, with a PowerShell 5.1 alternative — enter your existing tunnel ID and direct Obsidian MCP URL.
- Stores your OpenAI Runtime API key and the Obsidian MCP token using **Windows DPAPI** for the current Windows user.
- Adds an optional **hidden, per-user startup shortcut** (no administrator permissions needed).
- Checks a JSON-RPC MCP initialize response, Runtime tunnel lookup, and client `doctor` before starting. Startup retries at most six times, then stops.
- Separates process status from a per-instance readiness endpoint; neither proves a complete remote ChatGPT round trip.
- Offers status, stop and uninstall helper scripts. Uses only PowerShell and Windows built-in tools.
- Does not bundle OpenAI executables or collect telemetry.

### Requirements

1. Windows 10/11 desktop and PowerShell 5.1+.
2. Obsidian with the existing [MCP Connector](https://github.com/istefox/obsidian-mcp-connector) enabled, and a token created in **Settings → MCP Connector → Access Control**.
3. The official `tunnel-client.exe` downloaded and extracted from [openai/tunnel-client releases](https://github.com/openai/tunnel-client/releases). Check published `SHA256SUMS.txt` before running downloaded executables.
4. An OpenAI Platform **Tunnel ID** and a Restricted Runtime API key with **Tunnels Read + Use** permission. See [the official documentation](https://github.com/openai/tunnel-client/blob/master/docs/end-user-guide.md).
5. A ChatGPT workspace with access to create a custom MCP plugin.

### Install

**Graphical prototype:** extract the complete source ZIP outside your vault and double-click `Setup-BrainBridge.vbs`. Select the official client, confirm you checked its published checksum, enter the tunnel ID, direct loopback `/mcp` URL and both secrets. Choose optional login startup, then **Install / Save → Start → Refresh status**. Installation performs connection checks. **Test connection** is also available separately. Secret fields are cleared after an action; re-enter them when saving after a separate test. Use **Stop** or **Uninstall** in the same window. See [the graphical guide](docs/GUI.fa.md).

Windows Script Host and Windows PowerShell 5.1 must be enabled. Organizational script policies may block this unsigned prototype. It does not override those policies or install a signed MSI/EXE. No admin elevation is requested.

Choose **English** or **فارسی** at the top of the blue/teal window. Labels, validation/status messages and uninstall confirmation follow the selection; technical inputs stay LTR and retain their values. The default is Persian; the choice lasts for the current session. The GUI includes official download, Tunnel management and Runtime key links, plus matching offline illustrated guides in both languages. External account links require internet access and your own login. Links never contain entered IDs or secrets.

**PowerShell alternative:**

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
