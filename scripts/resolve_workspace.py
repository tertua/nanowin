"""Read config.json and print resolved workspace path.

Usage: resolve_workspace.py <config_path> [root_dir]

If workspace path in config is relative, resolves against root_dir.
If root_dir not given, uses config_path's grandparent
(config.json is at <root>/data/config.json, so grandparent = root).
"""
import json, pathlib, sys

config_path = pathlib.Path(sys.argv[1])
if not config_path.exists():
    sys.stdout.write("(config not found)")
    sys.exit(1)

root = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else config_path.parent.parent

config = json.loads(config_path.read_text("utf-8"))
workspace = config.get("agents", {}).get("defaults", {}).get("workspace", "workspace")

p = pathlib.Path(workspace)
if p.is_absolute():
    resolved = p
else:
    resolved = (root / p).resolve()

sys.stdout.write(str(resolved))
