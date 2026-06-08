# Validates Home Assistant BamBuddy add-on repo metadata and config.
# Usage:
#   .\scripts\validate-build.ps1              # quick: YAML/JSON parse + add-on config checks
#   .\scripts\validate-build.ps1 -Mode full   # + workflow YAML and Dockerfile presence

param(
    [ValidateSet('quick', 'full')]
    [string]$Mode = 'quick'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $RepoRoot

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $Name (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

$validatePy = @'
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    import subprocess

    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml", "-q"])
    import yaml

REPO = Path(sys.argv[1])
MODE = sys.argv[2]
ADDON_DIRS = ["bambuddy", "bambuddy-beta", "bambuddy-daily"]
REQUIRED_CONFIG_KEYS = ("name", "version", "slug", "description", "arch")
EXPECTED_SLUGS = {
    "bambuddy": "bambuddy",
    "bambuddy-beta": "bambuddy_beta",
    "bambuddy-daily": "bambuddy_daily",
}
errors: list[str] = []


def load_yaml(path: Path):
    with path.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def load_json(path: Path):
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def check_yaml_tree(path: Path):
    try:
        load_yaml(path)
    except Exception as exc:  # noqa: BLE001
        errors.append(f"{path}: invalid YAML ({exc})")


def check_json_tree(path: Path):
    try:
        load_json(path)
    except Exception as exc:  # noqa: BLE001
        errors.append(f"{path}: invalid JSON ({exc})")


for rel in ADDON_DIRS:
    addon_dir = REPO / rel
    config_path = addon_dir / "config.yaml"
    if not config_path.is_file():
        errors.append(f"missing {config_path}")
        continue

    check_yaml_tree(config_path)
    if errors:
        continue

    config = load_yaml(config_path)
    if not isinstance(config, dict):
        errors.append(f"{config_path}: root must be a mapping")
        continue

    for key in REQUIRED_CONFIG_KEYS:
        if key not in config:
            errors.append(f"{config_path}: missing required key '{key}'")

    expected_slug = EXPECTED_SLUGS.get(rel)
    if expected_slug and config.get("slug") != expected_slug:
        errors.append(
            f"{config_path}: slug must be '{expected_slug}', got '{config.get('slug')}'"
        )

    if MODE == "full":
        dockerfile = addon_dir / "Dockerfile"
        if not dockerfile.is_file():
            errors.append(f"missing {dockerfile}")

for translations in REPO.glob("**/translations/*.yaml"):
    check_yaml_tree(translations)

repo_json = REPO / "repository.json"
if not repo_json.is_file():
    errors.append("missing repository.json")
else:
    check_json_tree(repo_json)
    data = load_json(repo_json)
    for key in ("name", "url", "maintainer"):
        if key not in data:
            errors.append(f"repository.json: missing required key '{key}'")

if MODE == "full":
    for workflow in (REPO / ".github" / "workflows").glob("*.y*ml"):
        check_yaml_tree(workflow)

if errors:
    print("Validation errors:", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    sys.exit(1)

print(f"Validated add-ons, translations, and repository.json ({MODE} mode).")
'@

Invoke-Step 'add-on metadata and YAML/JSON' {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $validatePy | python - $RepoRoot $Mode
    } finally {
        $ErrorActionPreference = $prev
    }
}

Write-Host "All validation steps passed ($Mode)." -ForegroundColor Green
