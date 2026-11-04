# Primary references checked while drafting — 2026-11-04

These are references, not bundled copies of third-party documentation. Re-check
account UI, permission model and current API version at deployment time.

- **S1 — Manus Custom MCP Servers:** https://manus.im/docs/integrations/custom-mcp
  Supports a hosted HTTPS custom MCP endpoint and API-key/Bearer/other required
  authentication. Covers deployment and connection verification.
- **S2 — Manus Connectors feature page:** https://www.manus.im/features/connectors
  Describes custom MCP URL/command/JSON and Custom API credentials. Account UI
  availability must be observed; no specific user's entitlement is claimed.
- **S3 — OpenAI Secure MCP Tunnel:** https://developers.openai.com/api/docs/guides/secure-mcp-tunnels
  Describes supported OpenAI surfaces. No inference of a ready Manus/Claude route.
- **S4 — Manus API v2 Connectors:** https://open.manus.im/docs/v2/connectors
  Connector authorization, real connector UUIDs and message.connectors.
- **S5 — Codex AGENTS.md:** https://developers.openai.com/codex/guides/agents-md
  Redirects to https://learn.chatgpt.com/docs/agent-configuration/agents-md .
  Verify effective instructions for the runtime; a Vault note alone is not a
  global rule for every existing cloud task.
- **S6 — MCP Streamable HTTP:** https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
- **S7 — MCP Authorization:** https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization
- **S8 — Official MCP Python SDK:** https://github.com/modelcontextprotocol/python-sdk
- **S9 — Obsidian Help:** https://help.obsidian.md/

- **S10 — Manus API Connectors:** https://open.manus.im/docs/v2/connectors
  Requires authorizing/installing a connector in the Manus web account before using its account-specific UUID in API tasks.
- **S11 — Manus API connector.list:** https://open.manus.im/docs/v2/connector.list
  Lists account-installed connectors and their IDs/types; custom MCP IDs must be discovered at runtime.
- **S12 — Manus API task.create:** https://open.manus.im/docs/v2/task.create
  Defines v2 task creation, API key/OAuth authentication, and `message.connectors` selection.
- **S13 — Manus API Task Lifecycle:** https://open.manus.im/docs/v2/task-lifecycle
  Defines asynchronous polling, waiting states, and background-job completion checks.

Local incident history, actual user paths, account/tunnel identifiers, private
receipts and archive listings are intentionally NOT included here. User-specific
deployment coordinates belong in the private local-owner handoff.
