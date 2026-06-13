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

# ── Find target directory ──────────────────────────────────────────
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

# ── Helper ─────────────────────────────────────────────────────────
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


def _patch_log_handlers(content: str, cond_var: str, old_upstream: str, new_block: str, label: str) -> tuple[str, int]:
    """Patch nanobot CLI log handlers via 3 small regex subs (+ upstream full-block fallback).

    Regex subs (idempotent, no-op if pattern not matched):
      A. `logger.remove(_log_handler_id)` → `logger.remove()`
         Fixes the DEBUG leak: removes ALL handlers, not just the custom one.
      B. File logger level INFO/WARNING → DEBUG
      C. Conditional `if X: logger.add(sys.stderr, level="DEBUG", ...)` → unconditional ternary
         Always shows INFO+ in terminal; --{cond_var} elevates to DEBUG.

    For fresh upstream (no _log_dir at all), a full-block replace installs the new setup.
    For other unrecognised states, post-condition check fails and a [WARN] is logged —
    delete data\\.lockhead and re-run setup.bat to recover.
    """
    # Fresh upstream state: try full-block replace first (before sentinel check,
    # because a previous function's patch may have added _log_dir.mkdir).
    if old_upstream and old_upstream in content:
        content = content.replace(old_upstream, new_block)
        print(f"  [OK] {label} (upstream full-block)")
        return content, 1

    # Sentinel: already fully patched (logger.remove() in log section + terminal ternary + file DEBUG)
    if "_log_dir.mkdir" in content:
        log_section = content[content.index("_log_dir.mkdir"):]
        if (
            "logger.remove()" in log_section
            and f'"DEBUG" if {cond_var} else "INFO"' in content
            and re.search(r'level="DEBUG",\s+rotation="1 day"', content)
        ):
            return content, 0  # SKIP

    # Partially patched: has _log_dir but sentinel failed → apply small regex subs
    if "_log_dir.mkdir" in content:
        n_total = 0

        # Sub A
        content, n = re.subn(r'logger\.remove\(_log_handler_id\)', 'logger.remove()', content)
        n_total += n

        # Sub B
        content, n = re.subn(
            r'(logger\.add\(\s*_log_dir / "nanobot_\{time:YYYY-MM-DD\}\.log",.*?level=)"(?:INFO|WARNING)"',
            r'\1"DEBUG"',
            content,
            flags=re.DOTALL,
        )
        n_total += n

        # Sub C
        cond_re = re.escape(cond_var)
        content, n = re.subn(
            r'    if ' + cond_re + r':\n        logger\.add\(\s*sys\.stderr,.*?level="DEBUG",\s*colorize=None,\s*filter=.*?,\s*\)\n',
            _STDERR_BLOCK.replace('__COND__', cond_var),
            content,
            flags=re.DOTALL,
        )
        n_total += n

        # Post-condition check
        log_section = content[content.index("_log_dir.mkdir"):]
        has_remove = "logger.remove()" in log_section
        has_terminal = f'"DEBUG" if {cond_var} else "INFO"' in content
        has_file_debug = re.search(r'level="DEBUG",\s+rotation="1 day"', content) is not None
        if has_remove and has_terminal and has_file_debug:
            print(f"  [OK] {label} ({n_total} regex sub(s))")
            return content, 1

        print(f"  [WARN] {label}: incomplete after subs — delete data\\.lockhead and re-run setup.bat")
        return content, 0

    print(f"  [WARN] {label}: pattern not found — version mismatch?")
    return content, 0

# ── 1. paths.py ────────────────────────────────────────────────────
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

# ── 2. loader.py ───────────────────────────────────────────────────
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

# ── 3. schema.py ───────────────────────────────────────────────────
def patch_schema(content: str) -> tuple[str, int]:
    return simple_replace(
        content,
        '    workspace: str = "~/.nanobot/workspace"',
        '    workspace: str = "data/workspace"',
        "schema.py default workspace",
    )

schema_changed = patch_file("schema.py", patch_schema)


# ── 4. commands.py ─────────────────────────────────────────────────
# commands.py is at nanobot/cli/commands.py, not nanobot/config/.
COMMANDS_TARGETS = [
    ROOT / "app" / "nanobot" / "cli" / "commands.py",
    ROOT / "bin" / "Lib" / "site-packages" / "nanobot" / "cli" / "commands.py",
]

commands_target = None
for p in COMMANDS_TARGETS:
    if p.exists():
        commands_target = p
        break

if commands_target is None:
    print("[ERROR] Cannot find nanobot/cli/commands.py.")
else:
    print(f"Commands file: {commands_target}")

def patch_serve(content):
    """4a. serve(): terminal=INFO (clean UX), file=DEBUG (full detail). --verbose elevates terminal to DEBUG."""
    old_upstream = (
        '    if verbose:\n'
        '        logger.enable("nanobot")\n'
        '    else:\n'
        '        logger.disable("nanobot")\n'
        '\n'
        '    runtime_config = _load_runtime_config(config, workspace)'
    )
    new = (
        '    runtime_config = _load_runtime_config(config, workspace)\n'
        '\n'
        '    # Terminal: INFO+ (heartbeat, warning, error). File: DEBUG (full detail, stack trace etc.).\n'
        '    # --verbose elevates terminal to DEBUG for ad-hoc debugging.\n'
        '    _log_dir = (runtime_config.workspace_path.parent / "logs").resolve()\n'
        '    _log_dir.mkdir(parents=True, exist_ok=True)\n'
        '    # Remove ALL existing handlers (incl. loguru default id=0 at DEBUG) so they do not leak through.\n'
        '    logger.remove()\n'
        + _STDERR_BLOCK.replace('__COND__', 'verbose') + '\n'
        '    logger.add(\n'
        '        _log_dir / "nanobot_{time:YYYY-MM-DD}.log",\n'
        '        format="{time:YYYY-MM-DD HH:mm:ss} | {level: <5} | {extra[channel]} | {message}",\n'
        '        level="DEBUG",\n'
        '        rotation="1 day",\n'
        '        retention="14 days",\n'
        '        filter=lambda record: record["extra"].setdefault("channel", "-") or True,\n'
        '    )'
    )
    return _patch_log_handlers(content, 'verbose', old_upstream, new, "4a. serve() terminal=INFO file=DEBUG")

def patch_gateway(content):
    """4b. gateway(): terminal=INFO (clean UX), file=DEBUG (full detail). --verbose elevates terminal to DEBUG."""
    old_upstream = (
        '    if verbose:\n'
        '        logger.remove(_log_handler_id)\n'
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
        '    cfg = _load_runtime_config(config, workspace)'
    )
    new = (
        '    cfg = _load_runtime_config(config, workspace)\n'
        '\n'
        '    # Terminal: INFO+ (heartbeat, warning, error). File: DEBUG (full detail, stack trace etc.).\n'
        '    # --verbose elevates terminal to DEBUG for ad-hoc debugging.\n'
        '    _log_dir = (cfg.workspace_path.parent / "logs").resolve()\n'
        '    _log_dir.mkdir(parents=True, exist_ok=True)\n'
        '    # Remove ALL existing handlers (incl. loguru default id=0 at DEBUG) so they do not leak through.\n'
        '    logger.remove()\n'
        + _STDERR_BLOCK.replace('__COND__', 'verbose') + '\n'
        '    logger.add(\n'
        '        _log_dir / "nanobot_{time:YYYY-MM-DD}.log",\n'
        '        format="{time:YYYY-MM-DD HH:mm:ss} | {level: <5} | {extra[channel]} | {message}",\n'
        '        level="DEBUG",\n'
        '        rotation="1 day",\n'
        '        retention="14 days",\n'
        '        filter=lambda record: record["extra"].setdefault("channel", "-") or True,\n'
        '    )'
    )
    return _patch_log_handlers(content, 'verbose', old_upstream, new, "4b. gateway() terminal=INFO file=DEBUG")

def patch_agent(content):
    """4c. agent(): terminal=INFO (heartbeat etc.), file=DEBUG (full detail). --logs elevates terminal to DEBUG."""
    old_upstream = (
        '\n    if logs:\n'
        '        logger.enable("nanobot")\n'
        '    else:\n'
        '        logger.disable("nanobot")'
    )
    new = (
        '\n'
        '    # Terminal: INFO+ (heartbeat, warning, error — so chat prompts stay uncluttered).\n'
        '    # File: DEBUG (full detail, stack trace etc.). --logs elevates terminal to DEBUG.\n'
        '    _log_dir = (config.workspace_path.parent / "logs").resolve()\n'
        '    _log_dir.mkdir(parents=True, exist_ok=True)\n'
        '    # Remove ALL existing handlers (incl. loguru default id=0 at DEBUG) so they do not leak through.\n'
        '    logger.remove()\n'
        + _STDERR_BLOCK.replace('__COND__', 'logs') + '\n'
        '    logger.add(\n'
        '        _log_dir / "nanobot_{time:YYYY-MM-DD}.log",\n'
        '        format="{time:YYYY-MM-DD HH:mm:ss} | {level: <5} | {extra[channel]} | {message}",\n'
        '        level="DEBUG",\n'
        '        rotation="1 day",\n'
        '        retention="14 days",\n'
        '        filter=lambda record: record["extra"].setdefault("channel", "-") or True,\n'
        '    )'
    )
    return _patch_log_handlers(content, 'logs', old_upstream, new, "4c. agent() terminal=INFO file=DEBUG")

def patch_multiline(content):
    """4d. _init_prompt_session(): set multiline=True untuk multi-baris input."""
    old = '        multiline=False,  # Enter submits (single line mode)'
    new = '        multiline=True,  # Enter → newline, Escape+Enter → submit'
    return simple_replace(content, old, new, "4d. _init_prompt_session() multiline=True")

if commands_target:
    content = commands_target.read_text("utf-8")
    commands_changed = 0
    content, ch = patch_serve(content)
    commands_changed += ch
    content, ch = patch_gateway(content)
    commands_changed += ch
    content, ch = patch_agent(content)
    commands_changed += ch
    content, ch = patch_multiline(content)
    commands_changed += ch
    if commands_changed:
        commands_target.write_text(content, "utf-8")
        print(f"  -> {commands_changed} patch(es) applied to commands.py")
    else:
        print("  -> No changes to commands.py")
else:
    commands_changed = 0

# ── 5. helpers.py ──────────────────────────────────────────────────
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
    """5. sync_workspace_templates(): check NANOBOT_HOME/../scripts/templates/ first."""
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
    return simple_replace(content, old, new, "5. helpers.py sync_workspace_templates custom templates")

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

# ── Summary ────────────────────────────────────────────────────────
total = paths_changed + loader_changed + schema_changed + commands_changed + helpers_changed
print(f"\nDone. {total} file(s) patched.")
if total:
    print("Please restart nanobot to apply changes.")
