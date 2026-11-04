#!/usr/bin/env python3
"""Create a Manus task using an installed ObSi KAR MCP connector.

This script does not provision a connector, gateway, Vault access, or file transfer.
Set MANUS_API_KEY through a local secret manager. Never pass it as a CLI argument.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener

API_ROOT = "https://api.manus.ai/v2"
DEFAULT_CONNECTOR_NAME = "ObSi KAR — Manus"


class ManusAPIError(RuntimeError):
    """Safe-to-display API error that never includes credentials or response body."""


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def select_mcp_connector(connectors: list[dict], name: str) -> str:
    matches = [
        item for item in connectors
        if item.get("name") == name and item.get("type") == "mcp"
        and isinstance(item.get("id"), str) and item["id"]
    ]
    if not matches:
        raise ManusAPIError(
            f"MCP connector {name!r} is not installed for this API account; "
            "add and test it in the Manus account first."
        )
    if len(matches) != 1:
        raise ManusAPIError(
            f"More than one MCP connector is named {name!r}; use a unique name."
        )
    return matches[0]["id"]


def build_task_payload(prompt: str, connector_id: str) -> dict:
    if not prompt.strip():
        raise ManusAPIError("Task prompt must not be empty.")
    if not connector_id:
        raise ManusAPIError("A connector ID discovered from connector.list is required.")
    return {"message": {"content": prompt, "connectors": [connector_id]}}


class ManusAPI:
    def __init__(self, api_key: str, opener=None):
        if not api_key or "\r" in api_key or "\n" in api_key:
            raise ManusAPIError("Set MANUS_API_KEY using a local secret manager.")
        self.api_key = api_key
        self.opener = opener or build_opener(NoRedirect())

    def request(self, method: str, route: str, payload: dict | None = None) -> dict:
        if route not in {"/connector.list", "/task.create"}:
            raise ManusAPIError("Unsupported Manus API route.")
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        request = Request(
            API_ROOT + route,
            data=data,
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
                "x-manus-api-key": self.api_key,
            },
            method=method,
        )
        try:
            with self.opener.open(request, timeout=30) as response:
                raw = response.read(2 * 1024 * 1024 + 1)
        except HTTPError as exc:
            raise ManusAPIError(
                f"Manus API returned HTTP {exc.code} for {route}; response body omitted."
            ) from None
        except (URLError, TimeoutError):
            raise ManusAPIError(
                f"Could not reach Manus API for {route}; check network and TLS."
            ) from None
        if len(raw) > 2 * 1024 * 1024:
            raise ManusAPIError("Manus API response exceeded the local size limit.")
        try:
            result = json.loads(raw)
        except (json.JSONDecodeError, UnicodeDecodeError):
            raise ManusAPIError("Manus API returned invalid JSON.") from None
        if not isinstance(result, dict) or result.get("ok") is False:
            error = result.get("error", {}) if isinstance(result, dict) else {}
            code = error.get("code") if isinstance(error, dict) else None
            suffix = f" ({code})" if isinstance(code, str) else ""
            raise ManusAPIError(f"Manus API request failed{suffix}.")
        return result

    def create_task(self, prompt: str, connector_name: str) -> dict:
        listed = self.request("GET", "/connector.list")
        connectors = listed.get("data")
        if not isinstance(connectors, list):
            raise ManusAPIError("connector.list response did not contain a connector list.")
        connector_id = select_mcp_connector(connectors, connector_name)
        created = self.request(
            "POST", "/task.create", build_task_payload(prompt, connector_id)
        )
        task_id = created.get("task_id")
        if not isinstance(task_id, str) or not task_id:
            raise ManusAPIError("task.create response did not contain a task_id.")
        output = {"task_id": task_id}
        task_url = created.get("task_url")
        if isinstance(task_url, str) and task_url.startswith("https://"):
            output["task_url"] = task_url
        return output


def read_prompt(args) -> str:
    if args.prompt is not None:
        return args.prompt
    try:
        return Path(args.prompt_file).read_text(encoding="utf-8")
    except OSError:
        raise ManusAPIError("Could not read the UTF-8 prompt file.") from None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--prompt", help="Task instruction; do not include secrets/private data")
    source.add_argument("--prompt-file", help="UTF-8 file containing the task instruction")
    parser.add_argument("--connector-name", default=DEFAULT_CONNECTOR_NAME)
    args = parser.parse_args()

    try:
        api = ManusAPI(os.environ.get("MANUS_API_KEY", ""))
        result = api.create_task(read_prompt(args), args.connector_name)
    except (ManusAPIError, OSError, ValueError) as exc:
        print(f"Blocked: {exc}")
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
