# ObSi KAR — Manus and multi-platform handoff

**Version:** 0.2.0 · **Status:** integration handoff + tested clients, NOT a deployed gateway.

This module adds a concrete delivery contract, a lossless manifest builder and a
reference API client for **the existing ObSi KAR intake worker**. It does not add
another Vault writer and does not change the existing Brain Bridge launcher.

Start with [the complete Persian handoff](HANDOFF.fa.md). For account setup and
programmatic Manus API v2 tasks, also read [the Manus API guide](docs/MANUS-API.fa.md)
and inspect the [safe task-creation example](examples/manus_api_task.py). The
receiving task must also read [the transport contract](docs/TRANSPORT.md) and
[security/deployment boundaries](docs/SECURITY.md) before taking action.

## Shipped vs not shipped

| Item | Status |
|---|---|
| Full Manus / local-owner handoff | Included |
| Per-client routing and instructions | Included |
| Lossless, streaming file manifest builder | Implemented; fixture-tested |
| Resumable chunked API client | Implemented against the contract; fixture-tested |
| Actual HTTP/MCP receiver | **NOT included**; integrate the contract into the existing local worker |
| Public HTTPS address / credentials | **NOT provisioned** |
| Live Manus, Claude or ChatGPT connection to this adapter | **NOT tested** |
| Manus API task example | Included; dynamically discovers account MCP connector ID; not live-tested |
| Existing OpenAI Secure MCP Tunnel | Left unchanged; external-client compatibility is not assumed |
| Directory/archive extraction, OCR, deep analysis | Receiver responsibilities; never inferred from upload |
| Full private Vault export | Never included |

The `/v1/...` paths below are a **new integration contract**, not claimed endpoints
in a pre-existing installation. The legacy `send apijoo` / `send blender` helper
must be inspected and extended by its local owner. Merely publishing these files
cannot make a cloud computer reach a user's Windows drive.

## Use after the local owner has deployed the adapter

Python 3.10+; standard library only:

```bash
python -m unittest discover -s tests -v
# Configure OBSI_KAR_URL and OBSI_KAR_TOKEN through the client's secret store.
# No literal keys in commands, source, screenshots or URLs.
python tools/obsi_client.py info
python tools/obsi_client.py search "approved project context"
python tools/obsi_client.py read <note-id-from-search>
python tools/obsi_client.py send ./selected-files --producer manus --project demo
python tools/obsi_client.py receipt <package-id>
```

The server binds credentials to the producer and permitted projects. The client
cannot grant itself access by changing `--producer` or `--project`. `received`
means verified transfer, **not** extracted/indexed/processed.

To generate only a local manifest, without network or modification of originals:

```bash
python tools/obsi_bundle.py ./selected-files --producer manus --project demo \
  --output ./manifest.json
```

ZIP/PDF/Office/image bytes remain opaque originals. ZIPs are not extracted or
executed. This utility is not a malware or secret scanner. Source directories
must be selected and stable; it is not an OS sandbox against a hostile same-user
process.

## Structure

- `HANDOFF.fa.md`: one complete task for Manus and the existing local owner.
- `docs/MANUS-API.fa.md`: account setup, API v2 connector selection, data flow and RUNA safeguards.
- `docs/TRANSPORT.md`: new REST contract and equivalent MCP tool surface.
- `docs/SECURITY.md`: privileges, privacy, networking and acceptance tests.
- `docs/SOURCES.md`: primary documentation verified when drafting.
- `config/profiles.example.json`: disabled, placeholder-only client profiles.
- `skill/SKILL.md`: reusable instruction; not installed by publication.
- `tools/`: manifest and transport client; no Vault writer.
- `examples/manus_api_task.py`: standard-library Manus task creator using `connector.list`.
- `tests/`: synthetic fixture tests; not live Windows / Manus evidence.
- `VALIDATION.json`: actual results and exclusions.

License: the enclosing repository's MIT license. No private archive, receipt,
Vault configuration, local user path, tunnel ID or real token is distributed.
