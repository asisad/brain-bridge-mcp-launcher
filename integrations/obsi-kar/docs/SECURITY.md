# Security and honest readiness

This kit does NOT contain a public endpoint, secret, server implementation,
production queue/writer, or complete Windows security boundary. It is a handoff
with a manifest tool and API client. Deploying it requires the existing local
ObSi KAR owner to implement and test the transport contract.

## Required before deployment

- Preserve the working OpenAI/Obsidian routes. No master tokens for external AIs.
- Separate identity for each client; disabled by default. Owner-only onboarding.
- Bind server scopes to credentials, not producer fields, folder names or prompts.
- HTTPS with real certificate validation; no credentials in URLs, logs or Git.
- The local receiver binds loopback behind an authorized HTTPS proxy/tunnel.
  Do not expose local REST/MCP admin ports directly. Obtain approval for any new
  externally reachable endpoint, private-data scope, account or paid service.
- Read access to private notes discloses them to the chosen AI provider. Scope
  and consent are required; write-to-Inbox access does not grant read-all.
- All arbitrary formats are inert bytes; no scripts/macros, automatic extraction
  of nested archives, plugins installation, restore or destructive cleanup.
- Source symlink/hardlink checks in the client are defense in depth, NOT complete
  OS race resistance against malicious processes that can alter a selected root.
  Freeze a selected source; enforce receiver paths, handles, ACLs and quotas locally.
- Secret scanning is not implemented by the manifest utility. An authorized
  producer/local privacy gate must check for credentials before network transfer.
- Whole files, raw archives, receipts and runtime config never belong in this
  public repository. A public handoff is not permission to publish private data.
- Use a fresh local backup before configuration changes and preserve old routes.
  Rollback stops the new adapter and removes only its verified owned additions;
  never restore a compromised credential or overwrite user changes.

## Acceptance sequence (same task, no new writer)

1. Test receiver without credentials, wrong client, wrong project and expired token.
2. Verify scope-filtered search/read and non-leakage across client namespaces.
3. Transfer a small mixed-format synthetic folder; compare every original hash.
4. Test interrupted chunk/restart/resume, duplicate package and conflicting revision.
5. Hand the complete package to the **existing worker**; observe separate received
   and processed receipts plus actual Obsidian readback and links.
6. Check outside-scope state; explain concurrent runtime changes without claiming
   byte-for-byte preservation without evidence.
7. Test large-file capacity separately using a disclosed synthetic size and limits.
8. Finally send one user-selected real package; no blanket archive ingestion.

All testing in this distribution is synthetic and client-side. It does not prove
endpoint deployment, Manus account configuration, OS ACL isolation, archive
extraction, large-collection acceptance, or intelligence/RAG quality.
