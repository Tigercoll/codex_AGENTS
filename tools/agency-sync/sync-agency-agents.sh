#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

REPO_URL="https://github.com/msitarzewski/agency-agents.git"
BRANCH="main"
SOURCE_MIRROR_PATH="$CODEX_HOME/vendor_imports/agency-agents-source"
INSTALL_ROOT="$CODEX_HOME/agents/agency-agents"
MAP_JSON_PATH="$CODEX_HOME/agents/agency-agent-map.json"
MAP_MD_PATH="$CODEX_HOME/agents/agency-agent-map.md"
PROFILES_PATH="$SCRIPT_DIR/agency-agent-profiles.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-url)
      REPO_URL="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --source-mirror-path)
      SOURCE_MIRROR_PATH="$2"
      shift 2
      ;;
    --install-root)
      INSTALL_ROOT="$2"
      shift 2
      ;;
    --map-json-path)
      MAP_JSON_PATH="$2"
      shift 2
      ;;
    --map-md-path)
      MAP_MD_PATH="$2"
      shift 2
      ;;
    --profiles-path)
      PROFILES_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$SOURCE_MIRROR_PATH")"
mkdir -p "$(dirname "$MAP_JSON_PATH")"
mkdir -p "$(dirname "$MAP_MD_PATH")"

if [[ -d "$SOURCE_MIRROR_PATH/.git" ]]; then
  git -C "$SOURCE_MIRROR_PATH" fetch origin "$BRANCH" >/dev/null
  git -C "$SOURCE_MIRROR_PATH" checkout "$BRANCH" >/dev/null
  git -C "$SOURCE_MIRROR_PATH" reset --hard "origin/$BRANCH" >/dev/null
else
  rm -rf "$SOURCE_MIRROR_PATH"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$SOURCE_MIRROR_PATH" >/dev/null
fi

export REPO_URL BRANCH SOURCE_MIRROR_PATH INSTALL_ROOT MAP_JSON_PATH MAP_MD_PATH PROFILES_PATH

python3 - <<'PY'
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

repo_url = os.environ["REPO_URL"]
branch = os.environ["BRANCH"]
source_mirror = pathlib.Path(os.environ["SOURCE_MIRROR_PATH"]).expanduser()
install_root = pathlib.Path(os.environ["INSTALL_ROOT"]).expanduser()
map_json_path = pathlib.Path(os.environ["MAP_JSON_PATH"]).expanduser()
map_md_path = pathlib.Path(os.environ["MAP_MD_PATH"]).expanduser()
profiles_path = pathlib.Path(os.environ["PROFILES_PATH"]).expanduser()

with profiles_path.open("r", encoding="utf-8") as fh:
    shared = json.load(fh)

category_dirs = shared["category_dirs"]
auto_route_profiles = shared["auto_route_profiles"]

if install_root.exists():
    shutil.rmtree(install_root)
install_root.mkdir(parents=True, exist_ok=True)

for category in category_dirs:
    src = source_mirror / category
    if src.exists():
        shutil.copytree(src, install_root / category, dirs_exist_ok=True)

def parse_front_matter(path: pathlib.Path):
    with path.open("r", encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    if len(lines) < 3 or lines[0].strip() != "---":
        return None
    data = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return data
        m = re.match(r"^\s*([A-Za-z0-9_-]+)\s*:\s*(.*)$", line)
        if m:
            data[m.group(1)] = m.group(2).strip().strip('"')
    return None

def convert_to_key(slug: str) -> str:
    return re.sub(r"-+", "_", re.sub(r"[^A-Za-z0-9_-]", "-", slug))

def default_mode(category: str, slug: str) -> str:
    if category == "testing":
        return "qa"
    if "reviewer" in slug:
        return "reviewer"
    if "orchestrator" in slug:
        return "orchestrator"
    if "project-manager" in slug or "planner" in slug:
        return "planner"
    if category == "design":
        return "design"
    if category == "product":
        return "product"
    if category == "project-management":
        return "coordinator"
    return "executor"

def default_aliases(slug: str, label: str):
    return list(dict.fromkeys([
        slug,
        slug.replace("-", "_"),
        re.sub(r"[^a-z0-9]+", "-", label.lower()).strip("-")
    ]))

roles = {}

for file_path in sorted(install_root.rglob("*.md")):
    front = parse_front_matter(file_path)
    if not front or "name" not in front:
        continue
    relative_path = file_path.relative_to(install_root).as_posix()
    category = relative_path.split("/", 1)[0]
    slug = file_path.stem
    label = str(front["name"])
    roles[convert_to_key(slug)] = {
        "id": slug,
        "label": label,
        "path": str(file_path),
        "category": category,
        "mode": default_mode(category, slug),
        "spawn_as": "worker",
        "aliases": default_aliases(slug, label),
        "auto_route": False,
        "may_delegate_children": False,
        "recommended_child_depth_limit": 0,
        "source_relative_path": relative_path
    }

for key, profile in auto_route_profiles.items():
    rel = profile["relativePath"].replace("\\", "/")
    role_path = install_root / pathlib.Path(rel)
    roles[key] = {
        "id": profile["id"],
        "label": profile["label"],
        "path": str(role_path),
        "category": rel.split("/", 1)[0],
        "mode": profile["mode"],
        "spawn_as": profile["spawn_as"],
        "aliases": profile["aliases"],
        "auto_route": profile["auto_route"],
        "may_delegate_children": profile["may_delegate_children"],
        "recommended_child_depth_limit": profile["recommended_child_depth_limit"],
        "source_relative_path": rel
    }

commit = subprocess.check_output(
    ["git", "-C", str(source_mirror), "rev-parse", "HEAD"],
    text=True
).strip()

source_info = {
    "repo": repo_url,
    "branch": branch,
    "commit": commit,
    "synced_at": __import__("datetime").datetime.now().astimezone().isoformat(),
    "source_mirror": str(source_mirror)
}

with (install_root / ".source.json").open("w", encoding="utf-8") as fh:
    json.dump(source_info, fh, ensure_ascii=False, indent=2)

map_json_path.parent.mkdir(parents=True, exist_ok=True)
with map_json_path.open("w", encoding="utf-8") as fh:
    json.dump({"version": 1, "source": source_info, "roles": roles}, fh, ensure_ascii=False, indent=2)

auto_route_roles = sorted(((k, v) for k, v in roles.items() if v["auto_route"]), key=lambda item: item[0])
all_roles = sorted(roles.items(), key=lambda item: item[0])

lines = [
    "# Agency Agent Map",
    "",
    f"- Source repo: {source_info['repo']}",
    f"- Branch: {source_info['branch']}",
    f"- Commit: {source_info['commit']}",
    f"- Synced at: {source_info['synced_at']}",
    f"- Install root: {install_root}",
    "",
    "## Auto-Route Roles",
    "",
    "| Key | Role ID | Mode | Delegates Children | Path |",
    "| --- | --- | --- | --- | --- |",
]
for key, value in auto_route_roles:
    lines.append(f"| {key} | {value['id']} | {value['mode']} | {value['may_delegate_children']} | {value['source_relative_path']} |")

lines.extend([
    "",
    "## All Roles",
    "",
    "| Key | Role ID | Category | Mode | Auto Route | Path |",
    "| --- | --- | --- | --- | --- | --- |",
])
for key, value in all_roles:
    lines.append(f"| {key} | {value['id']} | {value['category']} | {value['mode']} | {value['auto_route']} | {value['source_relative_path']} |")

map_md_path.parent.mkdir(parents=True, exist_ok=True)
map_md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

echo "Agency agents synchronized."
echo "Templates: $INSTALL_ROOT"
echo "Registry:  $MAP_JSON_PATH"
echo "Index:     $MAP_MD_PATH"
