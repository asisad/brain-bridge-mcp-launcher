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
    data = p.read_text("utf-8")
    assert not re.search(r"tunnel_[a-f0-9]{32}", data), p
    assert not re.search(r"sk-(?:proj-)?[a-zA-Z0-9_-]{20,}", data), p
    assert not re.search(r"C:\\Users\\[^\\\s]+", data), p
    assert "\x00" not in data, p
scripts = list((root / "scripts").glob("*.ps1"))
assert len(scripts) == 5
installer = (root / "scripts" / "Install-BrainBridge.ps1").read_text("utf-8")
runner = (root / "scripts" / "Start-BrainBridge.ps1").read_text("utf-8")
assert "ConvertFrom-SecureString" in installer
assert "ConvertTo-SecureString" in runner
assert "admin tunnels get" in runner
assert "MCP_DISCOVERY_EXTRA_HEADERS" in runner
print("PASS: package inventory and basic secret-pattern checks")
