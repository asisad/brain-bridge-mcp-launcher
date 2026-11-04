# ObSi KAR Transport v1 — integration contract, not a deployed service

Implement these routes **inside/alongside the existing ObSi KAR process and queue**.
This repository ships the client and tests, not the receiving service. Never point
this client at an unmodified Obsidian Local REST API or the legacy text-only sender.

## Authority and identity

Authenticate every request; bind the credential to a producer, project allowlist,
read scopes, write-to-staging scopes, expiry and quotas. A body field is not
permission. Reject cross-producer package lookups with a non-enumerating response.
Never accept client-chosen disk roots, callback URLs, Vault paths or shell commands.
Server registration is owner-only, outside the public tool surface.

The MCP facade and REST API share this identity, queue, validator, raw store and
controlled writer. A second Vault writer, queue with divergent rules or separate
read-all service is not permitted. Folder separation is not a security boundary.

## Routes

| Method/path | Input | Result |
|---|---|---|
| GET `/v1/capabilities` | scoped token | contract, actual identity/scopes/limits |
| POST `/v1/notes/search` | query, limit, optional cursor | authorized results only; opaque note IDs |
| POST `/v1/notes/read` | note_id, optional cursor | authorized content segment + hash/version/cursor |
| POST `/v1/packages` | bundle/3 manifest; Idempotency-Key | reservation or same reservation on replay |
| GET `/v1/packages/{id}/files/{index}` | identity-bound package | verified durable received_bytes |
| PUT `/v1/packages/{id}/files/{index}` | bytes + X-Offset + X-Chunk-SHA256 | durable received_bytes |
| POST `/v1/packages/{id}/commit` | package_id; Idempotency-Key | `received` only after all full hashes pass |
| GET `/v1/packages/{id}/receipt` | identity-bound package | package/member receipt; pending != processed |

### Capabilities example (illustrative, not live)

```json
{
  "contract": "obsi-kar-transport/1",
  "producer_id": "manus",
  "allowed_projects": ["demo"],
  "read_scope_ids": [],
  "max_files": 10000,
  "max_total_bytes": 2147483648,
  "max_chunk_bytes": 1048576,
  "receiver_ready": false,
  "writer_ready": false
}
```

Actual limits must be explicitly configured and reported; no truncation. Source
archive size, expanded size, nesting depth and member count are separate limits.
Client fixture tests do NOT verify GiB-sized real-world end-to-end ingestion.

### Bundle identity

`obsi-kar-bundle/3` fields: producer_id, project_id, revision, privacy_level,
source_kind (`file` or `directory`), files[], file_count, total_bytes, package_id.
Each file: relative path, bytes, SHA-256, advisory media_type. IDs are lowercase
`[a-z0-9][a-z0-9._-]{0,79}`. Package ID is SHA-256 of UTF-8 canonical JSON of all
other fields: sorted keys, compact separators, Unicode retained, no NaN. The
server independently recalculates it. Preserve origin/platform/agent/conversation
metadata in a separately validated provenance record; do not trust origin as auth.

Do not strip BOM or normalize the bytes that define file hashes. ZIPs remain
original container bytes. Archive-member inspection is a separate safe step;
never restore `.obsidian`, execute macros, or auto-install code found inside one.

### Reservation, chunks and commits

Reserve atomically under server-selected staging. Keep a durable transfer record;
quota includes outstanding reservations. Deny path traversal, absolute/UNC/ADS
paths, case/Unicode collisions, symlinks/reparse/hardlinks and duplicate members.
Do not deserialize pickles or execute untrusted input. MIME/extension is advisory.

Chunk write is at the server's durable expected offset. An exact replay of an
already committed chunk is acknowledged without appending again; changed bytes
at the same offset are a conflict. Hash the chunk and full file independently.
Persist progress so process restart resumes safely. Client has bounded retries;
server enforces per-client rate, total storage, concurrent uploads and retention.

Commit revalidates the full manifest, hashes and source scopes. Publish one job
atomically into the **existing queue** only when complete; retry cannot duplicate
it. No raw deletion or replacement. Do not expose a transfer directory to the old
watcher while it is partially written. A legacy watcher that treats each child as
a separate manual job needs an adapter; do not assume a new directory shape works.

`received` confirms durable receipt of selected bytes; it is not a readback from
Obsidian. The existing controlled writer issues the later processing receipt.

### Reading

The actual local owner chooses whether to read through the authenticated local
Obsidian API with an enforcing allowlist or through explicitly approved snapshots.
Search filters scopes BEFORE enumeration/scoring/snippets. Read never dereferences
a client-provided arbitrary path or URL. Note references do not expand permissions.
A snapshot response includes its revision/time so it cannot masquerade as live data.
Responses provide source ref, full-content hash, segment offsets, next cursor and
truncation; a hash alone is not evidence that the text supports a claim.

### Member receipt example

```json
{
  "package_id": "<64-hex-server-verified-id>",
  "state": "received",
  "processed": false,
  "members": [{
    "path": "articles/paper.pdf",
    "bytes": 1024,
    "sha256": "<original-sha256>",
    "received": true,
    "raw_preserved": true,
    "extraction": "pending",
    "indexing": "pending",
    "analysis": "not_started",
    "output_refs": []
  }],
  "counts": {"expected": 1, "received": 1, "processed": 0, "blocked": 0}
}
```

A final receipt must identify the actual output and readback verification for each
member. Never mark a folder processed because only its README was stored. Where
a source has no complete reference manifest, overall completeness remains unknown.

## Equivalent MCP facade

Use a maintained MCP SDK; do not confuse generic REST routes with MCP. Suggested
names (to be implemented and discovered, not assumed available):
`obsi_capabilities`, `obsi_search`, `obsi_read`, `obsi_begin_transfer`,
`obsi_transfer_status`, `obsi_commit_transfer`, `obsi_receipt`.
Bulk binary uploads use the same authenticated API rather than model-generated
base64. All facade operations call the same underlying functions as the REST API.
Follow the official MCP transport/auth docs in SOURCES. Validate Host/Origin, use
OAuth where the actual client requires it, and bind bearer credentials to this
resource. Do not forward a client token to unrelated upstreams.

## Failure responses

Use 401/403 for missing/invalid scopes; 409 for version/path/hash conflicts;
413 for configured limits; 422 for incomplete/unsafe manifest; 503 for receiver
or queue unavailable. Unknown receipt ID is not success. Never return secrets,
local exception traces or another user's filenames. Auth/access failures require
owner resolution, not fallback to an unrestricted path.
