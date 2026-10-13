from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
assert (ROOT / "skills/azure-devops/SKILL.md").is_file()
assert (ROOT / "skills/azure-devops/scripts/ado-workitems.ps1").is_file()
assert (ROOT / "qwen-extension.json").is_file()
skill = (ROOT / "skills/azure-devops/SKILL.md").read_text()
assert "qwen-orchestrator/skills" not in skill
assert "get-epic-features" in skill
print("Package structure and skill independence checks passed.")
