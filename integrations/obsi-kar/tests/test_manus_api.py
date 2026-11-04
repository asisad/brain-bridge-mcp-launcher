import io
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "examples"))
from manus_api_task import (  # noqa: E402
    API_ROOT,
    ManusAPI,
    ManusAPIError,
    build_task_payload,
    select_mcp_connector,
)


class FakeResponse(io.BytesIO):
    pass


class FakeManusAPI:
    def __init__(self):
        self.calls = []
        self.responses = [
            {"ok": True, "data": [
                {"id": "dynamically-found-id", "name": "ObSi KAR — Manus", "type": "mcp"},
                {"id": "builtin-id", "name": "ObSi KAR — Manus", "type": "builtin"},
            ]},
            {"ok": True, "task_id": "synthetic-task-id", "task_url": "https://manus.im/app/abc"},
        ]

    def request(self, method, route, payload=None):
        self.calls.append((method, route, payload))
        return self.responses.pop(0)


class ManusAPITests(unittest.TestCase):
    def test_selects_dynamic_mcp_not_builtin(self):
        found = select_mcp_connector([
            {"id": "wrong", "name": "ObSi KAR — Manus", "type": "builtin"},
            {"id": "right", "name": "ObSi KAR — Manus", "type": "mcp"},
        ], "ObSi KAR — Manus")
        self.assertEqual(found, "right")

    def test_missing_mcp_is_blocked(self):
        with self.assertRaises(ManusAPIError):
            select_mcp_connector([], "ObSi KAR — Manus")

    def test_duplicate_mcp_names_are_blocked(self):
        repeated = [
            {"id": "one", "name": "ObSi KAR — Manus", "type": "mcp"},
            {"id": "two", "name": "ObSi KAR — Manus", "type": "mcp"},
        ]
        with self.assertRaises(ManusAPIError):
            select_mcp_connector(repeated, "ObSi KAR — Manus")

    def test_task_payload_selects_only_discovered_connector(self):
        payload = build_task_payload("Read only the approved note.", "live-id-from-list")
        self.assertEqual(payload, {"message": {
            "content": "Read only the approved note.",
            "connectors": ["live-id-from-list"],
        }})

    def test_empty_prompt_is_blocked(self):
        with self.assertRaises(ManusAPIError):
            build_task_payload("  ", "connector-id")

    def test_task_creation_resolves_connector_then_creates_task(self):
        fake = FakeManusAPI()
        created = ManusAPI.create_task(fake, "Read an approved note.", "ObSi KAR — Manus")
        self.assertEqual(created["task_id"], "synthetic-task-id")
        self.assertEqual(fake.calls[0], ("GET", "/connector.list", None))
        self.assertEqual(fake.calls[1][0:2], ("POST", "/task.create"))
        self.assertEqual(fake.calls[1][2]["message"]["connectors"], ["dynamically-found-id"])

    def test_api_root_is_https(self):
        self.assertEqual(API_ROOT, "https://api.manus.ai/v2")


if __name__ == "__main__":
    unittest.main()
