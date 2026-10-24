# Obsidian shortcut lifecycle example

[راهنمای فارسی](README.fa.md) · [Validation boundaries](VALIDATION.md)

**Experimental Windows example, separate from the v0.2 graphical installer.** Open Obsidian through a shared shortcut and supervise a hidden official tunnel-client only while that Obsidian installation is running. Requires Windows PowerShell 5.1 and Windows Script Host; it does not request administrator access.

## Behavior and tradeoff

`Open-Obsidian.vbs` starts a hidden supervisor, which opens the configured Obsidian executable normally. The supervisor waits for authenticated local MCP readiness, launches the tunnel without a console, and checks its per-process loopback health endpoint and recent control-plane status. It retries exited clients with backoff and replaces clients that remain unhealthy for 90 seconds after detection. It stops the owned tunnel and exits after Obsidian closes, with a short shutdown grace period.

A mutex is scoped to the Windows user and installation directory. The tunnel is assigned to a kill-on-close Windows Job, so it cannot survive a supervisor crash. Secrets are passed only in the child environment; raw stdout/stderr is drained and discarded. Only fixed diagnostic events and process metadata are saved locally.

**This is a shortcut wrapper, not an Obsidian process-start hook.** Opening the executable directly, a pre-existing taskbar pin, an `obsidian://` link, or a Windows restored session may bypass it. Open the shared shortcut to attach the supervisor to an already running configured Obsidian. There is no resident login watcher or Startup entry in this example. Minimized Obsidian is still running.

## Manual setup with an existing connection

This example does not create accounts, keys or tokens. It expects your own working MCP endpoint and existing current-user DPAPI credentials in the format used by Brain Bridge. Stop any other runner for the **same tunnel** before starting it. Independent installation directories have independent locks; they must not poll the same tunnel concurrently.

1. Create a private, current-user-only installation folder outside your Vault and outside the source checkout, for example `%LOCALAPPDATA%\ObsidianTunnelExample`. Use the directory permissions of your existing Brain Bridge installation; this sample is not an ACL installer.
2. Copy `Launcher-Config.ps1`, `Start-ObsidianTunnel.ps1`, `Get-ObsidianTunnelStatus.ps1`, `Run-Hidden.vbs`, and `Open-Obsidian.vbs` into it.
3. Copy `launcher-config.example.json` there as `launcher-config.json`. Set `obsidian_exe`, `tunnel_exe`, your existing `tunnel_id`, and the direct loopback `/mcp` URL. Paths accept environment variables such as `%LOCALAPPDATA%`.
4. Verify your official tunnel-client download against its publisher's release checksum. Put that executable's SHA-256 into `tunnel_sha256`. A saved hash detects changes; it does not independently establish provenance.
5. Place **your own existing** `runtime-key.dpapi` and `obsidian-token.dpapi` in this private folder under the same Windows account. Never copy another person's credentials, upload these files, or commit the installation folder. This example never rewrites them.
6. Double-click `Open-Obsidian.vbs`, or create a desktop/Start shortcut targeting that file through `wscript.exe`. It opens Obsidian and the hidden supervisor together. This example does not replace existing shortcuts or remove existing Startup entries automatically; retain a backup before making those manual changes.

Example shortcut target after setup:

```text
%SystemRoot%\System32\wscript.exe //B //Nologo "%LOCALAPPDATA%\ObsidianTunnelExample\Open-Obsidian.vbs"
```

For a diagnostic start from your private installation directory:

```powershell
powershell.exe -NoProfile -File .\Start-ObsidianTunnel.ps1 -OpenObsidian
```

The scripts are unsigned and remain subject to organizational execution policy. The VBS entry points use process-scoped `ExecutionPolicy Bypass`, matching the prototype launch pattern; they do not change persistent Windows policy.

## Status and recovery

From the installation directory:

```powershell
powershell.exe -NoProfile -File .\Get-ObsidianTunnelStatus.ps1
```

`state/status.json` is a timestamped snapshot. The status helper checks process path, parent and creation time, and marks dead/stale supervisors rather than trusting an old `ready` value. `state/events.jsonl` contains bounded diagnostic events; one rotated copy is retained. Keep diagnostics local.

Local `ready` is not a remote ChatGPT round trip; the `remote_e2e` field says so explicitly. Verify a harmless read-only MCP operation from your own connected ChatGPT account. Health detection, retry delays and network conditions affect recovery time. Authentication failures remain in `waiting_for_mcp`; the runner cannot repair revoked credentials.

To stop the example normally, close the configured Obsidian application. To resume, use the shared shortcut. Revert your manually edited shortcut to the original executable target to stop using the wrapper. The installation-specific rollback script from the originating machine is intentionally not distributed.

## Development checks

From the repository root on Windows, with Python available:

```powershell
python tests/check_package.py
powershell.exe -NoProfile -File tests/Parse-Scripts.ps1
powershell.exe -NoProfile -File tests/Shortcut-Launcher.ps1
```

The integration test uses temporary synthetic executables, an authenticated loopback MCP fixture and synthetic DPAPI secrets. It does not open your actual Obsidian, read a Vault, use real credentials or contact OpenAI. Its slow health recovery case takes roughly two minutes. `-SkipSlowRecovery` is available for a bounded quick development run; CI runs the full case.
