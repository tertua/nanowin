"""Patch nanobot source paths to never leak to ~/.nanobot/ or %USERPROFILE%.

Target priority:
  1. app/nanobot/config/ (source before pip install — fresh setup flow)
  2. site-packages/nanobot/config/ (already installed — existing setup)
"""
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent

# -- Find target directory ------------------------------------------
candidates = [
    ROOT / "app" / "nanobot" / "config",
    ROOT / "bin" / "Lib" / "site-packages" / "nanobot" / "config",
]

target = None
for p in candidates:
    if (p / "paths.py").exists() and (p / "loader.py").exists() and (p / "schema.py").exists():
        target = p
        break

if target is None:
    print("[ERROR] Cannot find nanobot/config/ directory.")
    for p in candidates:
        print(f"    {p}")
    sys.exit(1)

print(f"Target: {target}")

# -- Helper ---------------------------------------------------------
def patch_file(filename: str, patcher) -> int:
    """Read file, call patcher(content), write back if changed."""
    path = target / filename
    content = path.read_text("utf-8")
    new_content, changed = patcher(content)
    if changed:
        path.write_text(new_content, "utf-8")
    return changed

def simple_replace(content: str, old: str, new: str, label: str) -> tuple[str, int]:
    """Replace old text with new; report status."""
    if old in content:
        content = content.replace(old, new)
        print(f"  [OK] {label}")
        return content, 1
    if new in content:
        print(f"  [SKIP] {label}: already patched")
        return content, 0
    print(f"  [WARN] {label}: pattern not found — version mismatch?")
    return content, 0


_STDERR_BLOCK = '''    logger.add(
        sys.stderr,
        format=(
            "<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "
            "<level>{level: <5}</level> | "
            "<cyan>{extra[channel]}</cyan> | "
            "<level>{message}</level>"
        ),
        level="DEBUG" if __COND__ else "INFO",
        colorize=None,
        filter=lambda record: record["extra"].setdefault("channel", "-") or True,
    )'''


_FILE_LOG_BLOCK = '''    logger.add(
        _log_dir / "nanobot_{time:YYYY-MM-DD}.log",
        format="{time:YYYY-MM-DD HH:mm:ss} | {level: <5} | {extra[channel]} | {message}",
        level="DEBUG",
        rotation="1 day",
        retention="14 days",
        filter=lambda record: record["extra"].setdefault("channel", "-") or True,
    )'''


def _serve_new_block() -> str:
    return (
        '    runtime_config = _load_runtime_config(config, workspace)\n'
        '\n'
        '    # Nanowin: terminal=INFO (clean UX), file=DEBUG (full detail). --verbose elevates terminal to DEBUG.\n'
        '    _log_dir = (runtime_config.workspace_path.parent / "logs").resolve()\n'
        '    _log_dir.mkdir(parents=True, exist_ok=True)\n'
        '    logger.remove()\n'
        + _STDERR_BLOCK.replace('__COND__', 'verbose') + '\n'
        + _FILE_LOG_BLOCK
    )


def _agent_new_block() -> str:
    return (
        '    # Nanowin: no terminal logs by default (chat stays clean); file=DEBUG always.\n'
        '    # --logs adds stderr DEBUG. loguru is imported locally (agent.py has no logger import).\n'
        '    from loguru import logger\n'
        '    _log_dir = (runtime_config.workspace_path.parent / "logs").resolve()\n'
        '    _log_dir.mkdir(parents=True, exist_ok=True)\n'
        '    logger.remove()\n'
        '    if logs:\n'
        '        logger.add(\n'
        '            sys.stderr,\n'
        '            format=(\n'
        '                "<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "\n'
        '                "<level>{level: <5}</level> | "\n'
        '                "<cyan>{extra[channel]}</cyan> | "\n'
        '                "<level>{message}</level>"\n'
        '            ),\n'
        '            level="DEBUG",\n'
        '            colorize=None,\n'
        '            filter=lambda record: record["extra"].setdefault("channel", "-") or True,\n'
        '        )\n'
        + _FILE_LOG_BLOCK
    )

# -- 1. paths.py ----------------------------------------------------
def patch_paths(content: str) -> tuple[str, int]:
    c, changed = content, 0
    patterns = [
        ('Path.home() / ".nanobot" / "workspace"',
         '(get_config_path().parent / "workspace")',
         "paths.py get_workspace_path fallback"),
        ('default = Path.home() / ".nanobot" / "workspace"',
         'default = get_config_path().parent / "workspace"',
         "paths.py is_default_workspace fallback"),
        ('Path.home() / ".nanobot" / "history" / "cli_history"',
         'get_data_dir() / ".cli_history"',
         "paths.py get_cli_history_path"),
        ('Path.home() / ".nanobot" / "bridge"',
         'get_data_dir() / "bridge"',
         "paths.py get_bridge_install_dir"),
        ('Path.home() / ".nanobot" / "sessions"',
         'get_data_dir() / "sessions"',
         "paths.py get_legacy_sessions_dir"),
    ]
    for old, new, label in patterns:
        c, ch = simple_replace(c, old, new, label)
        changed += ch
    return c, changed

paths_changed = patch_file("paths.py", patch_paths)

# -- 2. loader.py ---------------------------------------------------
def patch_loader(content: str) -> tuple[str, int]:
    old = """def get_config_path() -> Path:
    \"\"\"Get the configuration file path.\"\"\"
    if _current_config_path:
        return _current_config_path
    return Path.home() / \".nanobot\" / \"config.json\""""

    new = """def get_config_path() -> Path:
    \"\"\"Get the configuration file path.\"\"\"
    if _current_config_path:
        return _current_config_path
    # Portable: honor NANOBOT_HOME before falling back to ~/.nanobot
    home = os.environ.get(\"NANOBOT_HOME\")
    if home:
        return Path(home) / \"config.json\"
    return Path.home() / \".nanobot\" / \"config.json\""""

    return simple_replace(content, old, new, "loader.py get_config_path NANOBOT_HOME")

loader_changed = patch_file("loader.py", patch_loader)

# -- 3. schema.py ---------------------------------------------------
def patch_schema(content: str) -> tuple[str, int]:
    return simple_replace(
        content,
        '    workspace: str = "~/.nanobot/workspace"',
        '    workspace: str = "data/workspace"',
        "schema.py default workspace",
    )

schema_changed = patch_file("schema.py", patch_schema)


# -- 4. serve() / agent() logging ---------------------------------
# Upstream v0.2.2+ refactored CLI logging: serve()/agent() now call
# `_set_nanobot_logs(<flag>)` (nanobot/cli/log_control.py) instead of toggling
# loguru handlers inline. Replace that call with nanowin's own handlers:
# terminal=INFO (clean UX) or DEBUG with --verbose/--logs; file=DEBUG always.
# serve() lives in commands.py; agent() moved to cli/agent.py (no loguru import there).
SERVE_TARGETS = [
    ROOT / "app" / "nanobot" / "cli" / "commands.py",
    ROOT / "bin" / "Lib" / "site-packages" / "nanobot" / "cli" / "commands.py",
]
AGENT_TARGETS = [
    ROOT / "app" / "nanobot" / "cli" / "agent.py",
    ROOT / "bin" / "Lib" / "site-packages" / "nanobot" / "cli" / "agent.py",
]


def patch_serve(content: str) -> tuple[str, int]:
    """4a. serve() (commands.py): terminal=INFO, file=DEBUG. --verbose elevates terminal to DEBUG."""
    old = (
        '    _set_nanobot_logs(verbose)\n'
        '\n'
        '    runtime_config = _load_runtime_config(config, workspace)'
    )
    return simple_replace(content, old, _serve_new_block(), "4a. serve() terminal=INFO file=DEBUG")


def patch_agent(content: str) -> tuple[str, int]:
    """4b. agent() (cli/agent.py): no terminal logs by default, file=DEBUG. --logs adds stderr DEBUG."""
    return simple_replace(
        content,
        '    _set_nanobot_logs(logs)',
        _agent_new_block(),
        "4b. agent() no-terminal logs by default file=DEBUG",
    )


commands_changed = 0
serve_target = None
for p in SERVE_TARGETS:
    if p.exists():
        serve_target = p
        break

if serve_target:
    print(f"Serve file: {serve_target}")
    content = serve_target.read_text("utf-8")
    content, ch = patch_serve(content)
    commands_changed += ch
    if ch:
        serve_target.write_text(content, "utf-8")
        print("  -> serve() patched in commands.py")
else:
    print("[INFO] nanobot/cli/commands.py not found, skipping serve patch.")

agent_target = None
for p in AGENT_TARGETS:
    if p.exists():
        agent_target = p
        break

if agent_target:
    print(f"Agent file: {agent_target}")
    content = agent_target.read_text("utf-8")
    content, ch = patch_agent(content)
    commands_changed += ch
    if ch:
        agent_target.write_text(content, "utf-8")
        print("  -> agent() patched in agent.py")
else:
    print("[INFO] nanobot/cli/agent.py not found, skipping agent patch.")

if commands_changed:
    print(f"  -> {commands_changed} patch(es) applied to CLI logging")
else:
    print("  -> No changes to CLI logging")

# -- 5. gateway.py --------------------------------------------------
# Gateway command moved to nanobot/cli/gateway.py in upstream v0.2.2+
GATEWAY_TARGETS = [
    ROOT / "app" / "nanobot" / "cli" / "gateway.py",
    ROOT / "bin" / "Lib" / "site-packages" / "nanobot" / "cli" / "gateway.py",
]

gateway_target = None
for p in GATEWAY_TARGETS:
    if p.exists():
        gateway_target = p
        break

if gateway_target is None:
    print("[INFO] nanobot/cli/gateway.py not found (older upstream?), skipping gateway patches.")
else:
    print(f"Gateway file: {gateway_target}")

def patch_gateway_logging(content):
    """5. gateway.py: terminal=INFO (clean UX), file=DEBUG (full detail). --verbose elevates terminal to DEBUG."""
    # The gateway.py has a configure_logging function that only logs when verbose=True
    # We need to patch it to always log to file (DEBUG) and conditionally to terminal (INFO/DEBUG)
    old_configure = (
        '    def configure_logging(verbose: bool) -> None:\n'
        '        if not verbose:\n'
        '            return\n'
        '        logger.remove(log_handler_id)\n'
        '        logger.add(\n'
        '            sys.stderr,\n'
        '            format=(\n'
        '                "<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "\n'
        '                "<level>{level: <5}</level> | "\n'
        '                "<cyan>{extra[channel]}</cyan> | "\n'
        '                "<level>{message}</level>"\n'
        '            ),\n'
        '            level="DEBUG",\n'
        '            colorize=None,\n'
        '            filter=lambda record: record["extra"].setdefault("channel", "-") or True,\n'
        '        )'
    )
    new_configure = (
        '    def configure_logging(verbose: bool) -> None:\n'
        '        import os as _os\n'
        '        # Terminal: INFO+ (heartbeat, warning, error). File: DEBUG (full detail).\n'
        '        # --verbose elevates terminal to DEBUG for ad-hoc debugging.\n'
        '        _log_dir = None\n'
        '        try:\n'
        '            from nanobot.config.loader import load_config as _lc, get_config_path as _gcp\n'
        '            _cfg = _lc()\n'
        '            _log_dir = (_cfg.workspace_path.parent / "logs").resolve()\n'
        '            _log_dir.mkdir(parents=True, exist_ok=True)\n'
        '        except Exception:\n'
        '            pass\n'
        '        # Remove ALL existing handlers (incl. loguru default id=0 at DEBUG)\n'
        '        logger.remove()\n'
        '        # Terminal: conditional on verbose\n'
        '        if verbose:\n'
        '            logger.add(\n'
        '                sys.stderr,\n'
        '                format=(\n'
        '                    "<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "\n'
        '                    "<level>{level: <5}</level> | "\n'
        '                    "<cyan>{extra[channel]}</cyan> | "\n'
        '                    "<level>{message}</level>"\n'
        '                ),\n'
        '                level="DEBUG",\n'
        '                colorize=None,\n'
        '                filter=lambda record: record["extra"].setdefault("channel", "-") or True,\n'
        '            )\n'
        '        else:\n'
        '            logger.add(\n'
        '                sys.stderr,\n'
        '                format=(\n'
        '                    "<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "\n'
        '                    "<level>{level: <5}</level> | "\n'
        '                    "<cyan>{extra[channel]}</cyan> | "\n'
        '                    "<level>{message}</level>"\n'
        '                ),\n'
        '                level="INFO",\n'
        '                colorize=None,\n'
        '                filter=lambda record: record["extra"].setdefault("channel", "-") or True,\n'
        '            )\n'
        '        # File: always DEBUG\n'
        '        if _log_dir:\n'
        '            logger.add(\n'
        '                _log_dir / "nanobot_{time:YYYY-MM-DD}.log",\n'
        '                format="{time:YYYY-MM-DD HH:mm:ss} | {level: <5} | {extra[channel]} | {message}",\n'
        '                level="DEBUG",\n'
        '                rotation="1 day",\n'
        '                retention="14 days",\n'
        '                filter=lambda record: record["extra"].setdefault("channel", "-") or True,\n'
        '            )'
    )
    return simple_replace(content, old_configure, new_configure, "5. gateway.py logging terminal=INFO file=DEBUG")

gateway_changed = 0
if gateway_target:
    content = gateway_target.read_text("utf-8")
    content, ch = patch_gateway_logging(content)
    gateway_changed += ch
    if gateway_changed:
        gateway_target.write_text(content, "utf-8")
        print(f"  -> {gateway_changed} patch(es) applied to gateway.py")
    else:
        print("  -> No changes to gateway.py")


# -- 6. helpers.py --------------------------------------------------
HELPERS_TARGETS = [
    ROOT / "app" / "nanobot" / "utils" / "helpers.py",
    ROOT / "bin" / "Lib" / "site-packages" / "nanobot" / "utils" / "helpers.py",
]

helpers_target = None
for p in HELPERS_TARGETS:
    if p.exists():
        helpers_target = p
        break

if helpers_target is None:
    print("[ERROR] Cannot find nanobot/utils/helpers.py.")
else:
    print(f"Helpers file: {helpers_target}")

def patch_sync_workspace_templates(content: str) -> tuple[str, int]:
    """6. sync_workspace_templates(): check NANOBOT_HOME/../scripts/templates/ first."""
    # Guards idempotency: `old` is a prefix of the injected block, so without
    # this marker the pattern re-matches on every setup re-run and duplicates.
    _marker = "# Nanowin: prefer custom templates from NANOBOT_HOME/../scripts/templates/"
    if _marker in content:
        print("  [SKIP] 6. helpers.py sync_workspace_templates custom templates: already patched")
        return content, 0
    old = (
        '    try:\n'
        '        tpl = pkg_files("nanobot") / "templates"\n'
        '    except Exception:\n'
        '        return []\n'
        '    if not tpl.is_dir():\n'
        '        return []'
    )
    new = (
        '    try:\n'
        '        tpl = pkg_files("nanobot") / "templates"\n'
        '    except Exception:\n'
        '        return []\n'
        '    if not tpl.is_dir():\n'
        '        return []\n'
        '    # Nanowin: prefer custom templates from NANOBOT_HOME/../scripts/templates/\n'
        '    import os\n'
        '    _lite_nh = os.environ.get("NANOBOT_HOME")\n'
        '    if _lite_nh:\n'
        '        _lite_tpl = Path(_lite_nh).resolve().parent / "scripts" / "templates"\n'
        '        if _lite_tpl.is_dir():\n'
        '            tpl = _lite_tpl'
    )
    return simple_replace(content, old, new, "6. helpers.py sync_workspace_templates custom templates")

helpers_changed = 0
if helpers_target:
    content = helpers_target.read_text("utf-8")
    content, ch = patch_sync_workspace_templates(content)
    helpers_changed += ch
    if helpers_changed:
        helpers_target.write_text(content, "utf-8")
        print(f"  -> {helpers_changed} patch(es) applied to helpers.py")
    else:
        print("  -> No changes to helpers.py")

# -- 7. memory.py ---------------------------------------------------
MEMORY_TARGETS = [
    ROOT / "app" / "nanobot" / "agent" / "memory.py",
    ROOT / "bin" / "Lib" / "site-packages" / "nanobot" / "agent" / "memory.py",
]

memory_target = None
for p in MEMORY_TARGETS:
    if p.exists():
        memory_target = p
        break

if memory_target is None:
    print("[ERROR] Cannot find nanobot/agent/memory.py.")
else:
    print(f"Memory file: {memory_target}")

def patch_memory_init(content: str) -> tuple[str, int]:
    c, changed = content, 0
    patterns = [
        (
            '        self.memory_dir = ensure_dir(workspace / "memory")\n'
            '        self.memory_file = self.memory_dir / "MEMORY.md"\n'
            '        self.history_file = self.memory_dir / "history.jsonl"\n'
            '        self.legacy_history_file = self.memory_dir / "HISTORY.md"\n'
            '        self.soul_file = workspace / "SOUL.md"\n'
            '        self.user_file = workspace / "USER.md"\n'
            '        self._cursor_file = self.memory_dir / ".cursor"\n'
            '        self._dream_cursor_file = self.memory_dir / ".dream_cursor"',
            '        # Nanowin: pin memory to config workspace so memory survives workspace scope changes\n'
            '        _mem_ws = Path(os.environ["NANOBOT_WORKSPACE"]) if "NANOBOT_WORKSPACE" in os.environ else Path(os.environ["NANOBOT_HOME"]) / "workspace" if "NANOBOT_HOME" in os.environ else workspace\n'
            '        self.memory_dir = ensure_dir(_mem_ws / "memory")\n'
            '        self.memory_file = self.memory_dir / "MEMORY.md"\n'
            '        self.history_file = self.memory_dir / "history.jsonl"\n'
            '        self.legacy_history_file = self.memory_dir / "HISTORY.md"\n'
            '        self.soul_file = _mem_ws / "SOUL.md"\n'
            '        self.user_file = _mem_ws / "USER.md"\n'
            '        self._cursor_file = self.memory_dir / ".cursor"\n'
            '        self._dream_cursor_file = self.memory_dir / ".dream_cursor"',
            "memory.py __init__ pin memory paths to config workspace",
        ),
    ]
    for old, new, label in patterns:
        c, ch = simple_replace(c, old, new, label)
        changed += ch
    # GitStore must also track the config workspace, not the scoped one
    c, ch = simple_replace(
        c,
        '        self._git = GitStore(workspace, tracked_files=[',
        '        self._git = GitStore(_mem_ws, tracked_files=[',
        "memory.py __init__ GitStore workspace",
    )
    changed += ch
    return c, changed

memory_changed = 0
if memory_target:
    content = memory_target.read_text("utf-8")
    content, ch = patch_memory_init(content)
    memory_changed += ch
    if memory_changed:
        memory_target.write_text(content, "utf-8")
        print(f"  -> {memory_changed} patch(es) applied to memory.py")
    else:
        print("  -> No changes to memory.py")

# -- Summary --------------------------------------------------------
total = paths_changed + loader_changed + schema_changed + commands_changed + gateway_changed + helpers_changed + memory_changed
print(f"\nDone. {total} file(s) patched.")
if total:
    print("Please restart nanobot to apply changes.")
