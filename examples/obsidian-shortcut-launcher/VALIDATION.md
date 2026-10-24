# Validation boundaries

## Originating local deployment — 2026-10-24

An installation-specific predecessor was exercised on its originating Windows machine with the official tunnel-client `0.0.15` and Obsidian MCP Connector `2.12.1`:

| Check | Observation |
|---|---|
| Repeated hidden launcher starts | One supervisor and one tunnel remained |
| Tunnel process termination | Replacement became healthy in 34.5 seconds |
| Normal Obsidian close | Obsidian, supervisor and tunnel all exited |
| Real desktop shortcut launch after close | Connection became ready in 31.1 seconds |
| Start shortcut while already running | No duplicate supervisor or tunnel |
| Suspended/unresponsive tunnel process | Health timeout caused replacement; ready in 122.1 seconds |
| Remote read-only MCP health call after recovery | `status: ok`; the new tunnel's dispatcher and response-delivery counters each advanced from zero to one, with no delivery failure |
| Native window observation | Obsidian displayed normally; no supervisor or tunnel window was observed |
| Existing DPAPI files | Before/after hashes matched |

This is an originating-deployment observation, not an independent audit or proof that this public export has been run against real services on another machine. No Windows reboot or real internet/VPN interruption was performed. Direct executable/URI starts were not covered. The historical reason an older login-startup shortcut failed was not conclusively established.

No Vault notes were edited by the repair. Machine-specific paths, connection IDs, credentials, process IDs, raw diagnostics and the machine-specific rollback tool are not included in this public export.

## Public export

The export makes executable paths configurable, expands environment variables, scopes the single-instance mutex by current user and installation directory, pins the selected client hash and rejects inherited competing tunnel configuration. These are additional changes beyond the originating live deployment.

`tests/Shortcut-Launcher.ps1` exercises the exported files with temporary synthetic executables and an authenticated loopback MCP fixture. It checks configuration rejection, client hash mismatch, credential delivery without raw-output persistence, inherited-profile removal, duplicate launcher handling, process-crash recovery, sustained local authentication failure and recovery, the 90-second unresponsive-child path, app-close teardown, and preservation of synthetic DPAPI files. It does not access a real Vault or OpenAI account. Windows CI runs this test alongside the existing prototype checks.

Tests and local readiness are not a substitute for a real remote request in each user's own installation. This example remains unsigned and experimental; external account setup, credential provisioning, ACL installation and automatic shortcut migration are outside its scope.
