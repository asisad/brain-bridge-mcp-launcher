from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
required = [
    "README.md", "LICENSE", "SECURITY.md", "CHANGELOG.md", ".gitignore",
    "scripts/Install-BrainBridge.ps1", "scripts/Start-BrainBridge.ps1",
    "scripts/Status-BrainBridge.ps1", "scripts/Stop-BrainBridge.ps1",
    "scripts/Remove-BrainBridge.ps1",
    "docs/README.fa.md", "docs/ARCHITECTURE.md", "docs/ROADMAP.md",
    "docs/PUBLISH.md",
]
missing = [name for name in required if not (root / name).is_file()]
assert not missing, missing
for p in root.rglob("*"):
    if not p.is_file() or ".git" in p.parts:
        continue
    if p.suffix.lower() not in {".md", ".ps1", ".py", ".json", ".vbs", ".yml", ".txt"}:
        continue
    data = p.read_text("utf-8-sig")
    assert not re.search(r"tunnel_[a-f0-9]{32}", data), p
    assert not re.search(r"sk-(?:proj-)?[a-zA-Z0-9_-]{20,}", data), p
    assert not re.search(r"C:\\Users\\[^\\\s]+", data), p
    assert "\x00" not in data, p
scripts = list((root / "scripts").glob("*.ps1"))
assert len(scripts) >= 7
installer = (root / "scripts" / "Install-BrainBridge.ps1").read_text("utf-8")
runner = (root / "scripts" / "Start-BrainBridge.ps1").read_text("utf-8")
assert "ConvertFrom-SecureString" in installer
assert "ConvertTo-SecureString" in runner
core = (root / "scripts" / "BrainBridge.Core.ps1").read_text("utf-8-sig")
assert "admin tunnels get" not in runner
assert "MCP_DISCOVERY_EXTRA_HEADERS" in core
print("PASS: package inventory and basic secret-pattern checks")
