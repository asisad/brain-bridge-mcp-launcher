#!/usr/bin/env python3
"""Lossless manifest builder for ObSi KAR. No network, extraction or Vault writes.
Python >=3.10; standard library only. Copy this function into the existing intake
helper when integrating; do not run a second Vault writer.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import mimetypes
import os
from pathlib import Path, PurePosixPath
import re
import stat
import unicodedata

SCHEMA = "obsi-kar-bundle/3"
CHUNK = 1024 * 1024
MAX_FILES = 10000
MAX_BYTES = 8 * 1024**3
ID = re.compile(r"[a-z0-9][a-z0-9._-]{0,79}\Z")
RESERVED = re.compile(r"(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?\Z", re.I)


def stable_json(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def validate_id(value: str) -> str:
    if not isinstance(value, str) or not ID.fullmatch(value):
        raise ValueError("invalid identifier")
    return value


def safe_relative(value: str) -> str:
    if not isinstance(value, str) or not value or "\\" in value:
        raise ValueError("invalid relative path")
    if value.startswith("/") or "\x00" in value:
        raise ValueError("absolute/NUL path refused")
    parts = value.split("/")
    if any(p in ("", ".", "..") or p.endswith((" ", ".")) or
           any(ord(c) < 32 or c in ':<>|?*"' for c in p) or
           RESERVED.fullmatch(p) for p in parts):
        raise ValueError("unsafe or nonportable path")
    return value


def guarded(path: Path) -> os.stat_result:
    st = path.lstat()
    if stat.S_ISLNK(st.st_mode) or getattr(st, "st_file_attributes", 0) & 0x400:
        raise ValueError("symlink/reparse path refused")
    return st


def file_info(path: Path) -> tuple[int, str]:
    before = guarded(path)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ValueError("nonregular/hardlinked input refused")
    digest = hashlib.sha256()
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    with os.fdopen(fd, "rb") as stream:
        opened = os.fstat(stream.fileno())
        if (before.st_dev, before.st_ino) != (opened.st_dev, opened.st_ino):
            raise ValueError("source replaced during open")
        for block in iter(lambda: stream.read(CHUNK), b""):
            digest.update(block)
        after = os.fstat(stream.fileno())
    current = guarded(path)
    fields = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_nlink)
    if fields(before) != fields(after) or fields(after) != fields(current):
        raise ValueError("source changed while hashing")
    return before.st_size, digest.hexdigest()


def discover(source: Path):
    """Walk without following links; the caller must own/freeze the selected root."""
    source = source.absolute()
    for parent in reversed(source.parents):
        guarded(parent)
    st = guarded(source)
    if stat.S_ISREG(st.st_mode):
        yield source.name, source
    elif stat.S_ISDIR(st.st_mode):
        def walk(directory: Path, prefix: str = ""):
            with os.scandir(directory) as it:
                children = sorted(it, key=lambda e: e.name)
            for entry in children:
                p = Path(entry.path)
                st = guarded(p)
                rel = prefix + entry.name
                if stat.S_ISDIR(st.st_mode):
                    yield from walk(p, rel + "/")
                elif stat.S_ISREG(st.st_mode):
                    yield rel, p
                else:
                    raise ValueError("unsupported filesystem entry")
        yield from walk(source)
    else:
        raise ValueError("input must be a regular file or directory")


def build(source: Path, producer: str, project: str, revision: str = "1",
          privacy: str = "private", max_files: int = MAX_FILES,
          max_bytes: int = MAX_BYTES) -> dict:
    validate_id(producer); validate_id(project); validate_id(revision)
    if privacy not in {"public", "internal", "private", "highly_private"}:
        raise ValueError("invalid privacy level")
    if max_files < 1 or max_bytes < 1:
        raise ValueError("limits must be positive")
    files, names, total = [], set(), 0
    for rel, path in discover(source):
        safe_relative(rel)
        collision_key = unicodedata.normalize("NFC", rel).casefold()
        if collision_key in names:
            raise ValueError("case/unicode path collision")
        names.add(collision_key)
        if len(files) >= max_files:
            raise ValueError("file count limit exceeded")
        declared_size = path.lstat().st_size
        if total + declared_size > max_bytes:
            raise ValueError("byte limit exceeded")
        size, sha = file_info(path)
        total += size
        if total > max_bytes:
            raise ValueError("byte limit exceeded")
        files.append({"path": rel, "bytes": size, "sha256": sha,
                      "media_type": mimetypes.guess_type(rel)[0] or
                      "application/octet-stream"})
    if not files:
        raise ValueError("empty file collection")
    body = {"schema": SCHEMA, "producer_id": producer, "project_id": project,
            "revision": revision, "privacy_level": privacy,
            "source_kind": "directory" if source.is_dir() else "file",
            "files": files, "file_count": len(files), "total_bytes": total}
    body["package_id"] = hashlib.sha256(stable_json(body)).hexdigest()
    return body


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path)
    p.add_argument("--producer", required=True)
    p.add_argument("--project", required=True)
    p.add_argument("--revision", default="1")
    p.add_argument("--privacy", default="private")
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    try:
        source = args.source.absolute()
        output = args.output.absolute()
        if source.is_dir() and (output == source or source in output.parents):
            raise ValueError("manifest output must be outside source directory")
        data = build(source, args.producer, args.project, args.revision, args.privacy)
        with output.open("x", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"state": "manifest_created", "package_id": data["package_id"],
                          "file_count": data["file_count"], "total_bytes": data["total_bytes"]}))
        return 0
    except (OSError, ValueError):
        print("Manifest failed: unsafe/changed source, limits or output conflict. No upload occurred.")
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
