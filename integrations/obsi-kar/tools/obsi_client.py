#!/usr/bin/env python3
"""Client for the PROPOSED ObSi KAR Transport v1 contract, not the legacy sender.
Server integration is required. HTTPS with verified certificates; no redirects.
No OpenAI/Obsidian master credentials. Only a per-producer scoped gateway token.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler, HTTPSHandler
import ssl
from obsi_bundle import build, discover, file_info, stable_json

CONTRACT = "obsi-kar-transport/1"
MAX_RESPONSE = 2 * 1024 * 1024
CHUNK = 1024 * 1024

class TransferError(RuntimeError):
    pass

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

class Client:
    def __init__(self, base: str, token: str, *, allow_loopback_http: bool = False,
                 opener=None):
        url = urlsplit(base)
        local = allow_loopback_http and url.scheme == "http" and url.hostname in {
            "127.0.0.1", "localhost", "::1"}
        if (url.scheme != "https" and not local) or not url.hostname or \
           url.username or url.password or url.query or url.fragment:
            raise TransferError("An HTTPS gateway URL without embedded credentials is required")
        if len(token) < 24 or any(c in token for c in "\r\n"):
            raise TransferError("A scoped token is required via environment")
        self.base, self.token = base.rstrip("/"), token
        self.opener = opener or build_opener(NoRedirect(), HTTPSHandler(context=ssl.create_default_context()))

    def request(self, method: str, path: str, value=None, raw: bytes | None = None,
                headers: dict | None = None):
        if not path.startswith("/v1/") or "?" in path or "#" in path:
            raise TransferError("Invalid route")
        payload = raw if raw is not None else (stable_json(value) if value is not None else None)
        h = {"Authorization": "Bearer " + self.token, "Accept": "application/json",
             "Content-Type": "application/octet-stream" if raw is not None else "application/json"}
        h.update(headers or {})
        req = Request(self.base + path, data=payload, headers=h, method=method)
        # Routes in this contract are idempotent; retries never mean processed.
        for attempt in range(3):
            try:
                with self.opener.open(req, timeout=30) as response:
                    data = response.read(MAX_RESPONSE + 1)
                    if len(data) > MAX_RESPONSE:
                        raise TransferError("Oversized response")
                    result = json.loads(data)
                    if not isinstance(result, dict):
                        raise TransferError("Invalid JSON response")
                    return result
            except HTTPError as e:
                if e.code in {408, 429, 502, 503, 504} and attempt < 2:
                    time.sleep(0.25 * (2 ** attempt)); continue
                raise TransferError(f"Gateway HTTP {e.code}; response body not logged") from None
            except (URLError, TimeoutError):
                if attempt < 2:
                    time.sleep(0.25 * (2 ** attempt)); continue
                raise TransferError("Gateway unreachable or TLS validation failed") from None
            except (ValueError, UnicodeError):
                raise TransferError("Invalid JSON response") from None
        raise TransferError("Request failed")

    def capabilities(self):
        info = self.request("GET", "/v1/capabilities")
        if info.get("contract") != CONTRACT:
            raise TransferError("Transport contract not supported; do not bypass legacy restrictions")
        return info

    def send(self, source: Path, producer: str, project: str, revision="1", privacy="private"):
        caps = self.capabilities()
        if caps.get("producer_id") != producer or project not in caps.get("allowed_projects", []):
            raise TransferError("Producer/project is not authorized for this token")
        manifest = build(source, producer, project, revision, privacy,
                         max_files=int(caps["max_files"]), max_bytes=int(caps["max_total_bytes"]))
        chunk_size = min(CHUNK, int(caps["max_chunk_bytes"]))
        if chunk_size < 1:
            raise TransferError("Invalid negotiated chunk size")
        ident = manifest["package_id"]
        reservation = self.request("POST", "/v1/packages", manifest,
                                   headers={"Idempotency-Key": ident})
        if reservation.get("package_id") != ident:
            raise TransferError("Gateway returned a different package id")
        actual = dict(discover(source))
        for index, item in enumerate(manifest["files"]):
            path = actual[item["path"]]
            status = self.request("GET", f"/v1/packages/{ident}/files/{index}")
            offset = status.get("received_bytes")
            if type(offset) is not int or not 0 <= offset <= item["bytes"]:
                raise TransferError("Invalid resume position")
            # Recheck source before resuming; server must verify FULL hash at commit.
            if file_info(path) != (item["bytes"], item["sha256"]):
                raise TransferError("Source changed before transfer")
            with path.open("rb") as stream:
                stream.seek(offset)
                while offset < item["bytes"]:
                    data = stream.read(min(chunk_size, item["bytes"] - offset))
                    if not data:
                        raise TransferError("Source shortened during transfer")
                    reply = self.request("PUT", f"/v1/packages/{ident}/files/{index}", raw=data,
                        headers={"X-Offset": str(offset),
                                 "X-Chunk-SHA256": hashlib.sha256(data).hexdigest()})
                    offset += len(data)
                    if reply.get("received_bytes") != offset:
                        raise TransferError("Chunk acknowledgement mismatch")
            if file_info(path) != (item["bytes"], item["sha256"]):
                raise TransferError("Source changed; no commit issued")
        # Detect additions/removals/renames as well as modified source bytes.
        if build(source, producer, project, revision, privacy,
                 int(caps["max_files"]), int(caps["max_total_bytes"])) != manifest:
            raise TransferError("Source collection changed; no commit issued")
        reply = self.request("POST", f"/v1/packages/{ident}/commit", {"package_id": ident},
                             headers={"Idempotency-Key": ident})
        if reply.get("package_id") != ident or reply.get("state") != "received":
            raise TransferError("Commit did not confirm received")
        # Does not claim extracted, indexed or processed.
        return {"package_id": ident, "state": "received", "file_count": manifest["file_count"],
                "total_bytes": manifest["total_bytes"], "processed": False}

    def receipt(self, package_id: str):
        if not re.fullmatch(r"[a-f0-9]{64}", package_id):
            raise TransferError("Invalid package id")
        return self.request("GET", f"/v1/packages/{package_id}/receipt")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    s = p.add_subparsers(dest="action", required=True)
    s.add_parser("info")
    q = s.add_parser("search"); q.add_argument("query")
    r = s.add_parser("read"); r.add_argument("note_id"); r.add_argument("--cursor")
    t = s.add_parser("receipt"); t.add_argument("package_id")
    u = s.add_parser("send"); u.add_argument("source", type=Path)
    u.add_argument("--producer", required=True); u.add_argument("--project", required=True)
    u.add_argument("--revision", default="1"); u.add_argument("--privacy", default="private")
    args = p.parse_args()
    try:
        c = Client(os.environ.get("OBSI_KAR_URL", ""), os.environ.get("OBSI_KAR_TOKEN", ""))
        if args.action == "info": result = c.capabilities()
        elif args.action == "search":
            result = c.request("POST", "/v1/notes/search", {"query": args.query, "limit": 10})
        elif args.action == "read":
            result = c.request("POST", "/v1/notes/read", {"note_id": args.note_id, "cursor": args.cursor})
        elif args.action == "receipt": result = c.receipt(args.package_id)
        else: result = c.send(args.source, args.producer, args.project, args.revision, args.privacy)
        print(json.dumps(result, ensure_ascii=False, indent=2)); return 0
    except (TransferError, OSError, ValueError, KeyError):
        print("Blocked: check gateway readiness, scoped credentials, registration, source and receipt. No success is inferred.")
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
