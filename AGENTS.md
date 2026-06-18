# AGENTS.md — nanowin

Windows-portable runtime for [HKUDS/nanobot](https://github.com/HKUDS/nanobot). Runs on built-in Windows PowerShell 5.1+ (no PS7). Everything lives on a USB drive; touches zero host state.

- No test runner, linter, type checker, or CI.
- `setup.bat` fetches portable Python/Node/Git/gh into `bin/`. No host tools required.

## Commands (from repo root on Windows)

| Command | Action |
|---|---|
| `setup.bat` | One-shot install. Delete `data\.lockhead` to re-run. |
| `edit_env.bat` | Decrypt → notepad → re-encrypt. |
| `start-chat.bat` | CLI chat via `scripts\nanobot-agent.ps1`. |
| `start-gateway.bat` | Web gateway (WebUI :8765, API :8900). |
| `build-webui.bat` | npm install + build in `app\webui`, copy to site-packages. |
| `bin\python.exe scripts\healthcheck.py` | Post-install verification. |

Setup log: `setup_log.txt`. Runtime logs: `data\logs\nanobot_YYYY-MM-DD.log`.

## Architecture

```
setup.bat → .bat wrappers → powershell -File .ps1

scripts/
  nanobot-setup.ps1    # Orchestrator: dot-sources setup/*.ps1 in order
  nanobot-agent.ps1    # CLI launcher
  nanobot-gateway.ps1  # Gateway launcher (kills stale ports on startup, registers PowerShell.Exiting)
  init_portable.ps1    # Dot-sourced by all .ps1. Redirects USERPROFILE/HOME/TEMP/APPDATA/LOCALAPPDATA → data/.
                       # Sets NANOBOT_HOME, GH_CONFIG_DIR, PIP_CACHE_DIR, NPM_CONFIG_CACHE, NPM_CONFIG_PREFIX.
                       # Builds $PortablePaths, exports Load-EnvEncrypted.
  env_crypt.py         # AES-256-GCM + scrypt (encrypt/load/decrypt). --noninteractive uses NANOBOT_ENV_KEY.
  portable_paths.py    # Patches upstream nanobot source to never use ~/.nanobot.
                       # Targets: paths.py, loader.py, schema.py, cli/commands.py, utils/helpers.py,
                       # agent/memory.py.
  post_config.py       # Post-processes nanobot onboard config: adds custom/nvidia/aihubmix providers w/ ${VAR},
                       # CLI channel, disabledSkills, restrictToWorkspace.
  lockhead.py          # Writes .lockhead INI with host metadata (system + software sections).
  resolve_workspace.py # Reads workspace path from config.json; called by agent/gateway launchers.
  requirements-lite.txt # Pip dependency manifest (no pyproject.toml extras).
  install_webui.ps1    # npm install + build, copy into site-packages/nanobot/web/dist/.
  sync_webui.ps1       # Copy pre-built webui from data/webui/ to site-packages (manual drop-zone workflow).
  edit_env_helper.ps1  # Shows provider context during edit_env.bat flow.
  healthcheck.py, lockhead.py, unzip.vbs
  setup/               # Dot-sourced by nanobot-setup.ps1 in order:
    install_busybox.ps1 → install_python.ps1 → install_git.ps1 → install_gh.ps1 → install_nodejs.ps1
    → install_source.ps1 → install_deps.ps1
    setup_helpers.ps1    # Write-OK, Write-Step, Download-Helper, Extract-Helper
    download.ps1         # 3-method fallback
    extract.ps1          # 4-method fallback
  templates/           # Custom workspace templates (check NANOBOT_HOME/../scripts/templates/ first via patched helpers.py)
app/   # Upstream nanobot source; git clone or ZIP extract (gitignored)
bin/   # Portable BusyBox, Python, MinGit, Node.js, gh (gitignored)
data/  # config.json, .env.encrypted, .env_key, .lockhead, knowledge/, logs/, workspace/ (gitignored)
```

## Critical conventions

- **Whitelist `.gitignore`.** Starts with `/*` — add `!/path` for new tracked files. Tracked: `setup.bat`, `start-chat.bat`, `edit_env.bat`, `build-webui.bat`, `start-gateway.bat`, `scripts/**`, `README.md`, `SECURITY.md`, `AGENTS.md`, `LICENSE`, `.github/`, `.github/FUNDING.yml`, `.gitattributes`, `.gitignore`.
- **Line endings.** `.ps1`/`.bat`/`.vbs`/`.cmd` are CRLF (PS5.1 chokes on LF). `.py`/`.md`/`.json`/`.yml`/`.toml`/`.txt` are LF.
- **Hard-coded versions in `nanobot-setup.ps1`** (`$PyVer=3.12.3`, `$GitVer=2.54.0`, `$NodeVer=24.16.0`, `$GhVer=2.93.0`). Bump there — no manifest.
- **BusyBox single EXE** from `frippery.org/files/busybox/`. No archive; `Download-Helper` saves to `bin\busybox.exe`.
- **Python embed `.pth` patching** (`install_python.ps1`): uncomments `import site`, appends `Lib`, `Lib\site-packages`, `..\app`. Without this, pip and app/ imports fail.
- **`.env` encrypted at rest** (AES-256-GCM + scrypt). `edit_env.bat` is the only plaintext path. Launchers use `Load-EnvEncrypted` → `env_crypt.py load` → `.env.tmp` → process env → delete `.env.tmp`. Never commit a key.
- **`data\.env_key`** makes launcher non-interactive. Delete to force interactive passphrase prompt.
- **`data\.lockhead`** = setup-done sentinel (INI file). Short-circuits `nanobot-setup.ps1`. Delete to reset.
- **`NANOBOT_HOME`** overrides `~/.nanobot`. Set in `init_portable.ps1` to `data/`.
- **`NANOBOT_WORKSPACE`** full path to workspace dir from `config.json`, set in `init_portable.ps1` via `Resolve-Workspace`. Used by memory.py patch to pin MEMORY.md/history to config workspace regardless of WebUI scope changes.
- **New launchers must** define `$ROOT`, dot-source `scripts/init_portable.ps1`, call `Load-EnvEncrypted`. Don't inline.
- **Default config** (`post_config.py`): `model: openai/gpt-oss-120b`, `provider: nvidia`, `disabledSkills: ["summarize", "tmux"]`, `restrictToWorkspace: true`. Also registers `custom` (uses `${NANOBOT_CUSTOM_API_KEY}` + `${NANOBOT_CUSTOM_API_BASE}`) and `aihubmix` providers. `pathAppend` left empty — PATH inherited from parent process (correct regardless of USB drive letter/workspace location).
- **Gateway ports.** WebUI/WS on :8765, API :8900 (`/v1/chat/completions`, `/v1/models`). External tools use `:8900` as OpenAI API base.
- **Custom workspace templates** (`scripts/templates/`). `portable_paths.py` patches `sync_workspace_templates()` to check `{NANOBOT_HOME}/../scripts/templates/` first. Falls back to upstream defaults silently if templates dir missing.
- **Patches upstream source** (`portable_paths.py`). Rewrites `paths.py`, `loader.py`, `schema.py`, `cli/commands.py`, `utils/helpers.py`, `agent/memory.py`. Logs `[WARN] pattern not found` for misses — check after upstream bump. The `commands.py` log-handler patch is post-condition-checked (sentinels: `logger.remove()` + `"DEBUG" if X else "INFO"` + `level="DEBUG", rotation="1 day"`). Memory pin patch ensures `MemoryStore` always uses config workspace (`NANOBOT_HOME/workspace`) so memory survives WebUI workspace scope changes.
- **`pip install --no-deps` wipes webui `dist/`.** Re-run `build-webui.bat` after every `setup.bat`. `sync_webui.ps1` is the manual drop-zone alternative (reads from `data/webui/`).
- **Upstream ZIP install** does not include `app/webui/`. Only git clone does. `build-webui.bat` checks for `app/webui/package.json` and fails early.
- **npm only for webui builds.** Bun's HOME-relative package store breaks on exFAT/FAT32. npm's flat `node_modules/` works on any filesystem.
- **`.bat` files are thin wrappers** — check `where powershell`, call `.ps1`, pause on error. Don't edit for logic.
- **Language rule.** Chat output to user: formal Indonesian. Everything else (code, comments, docs, logs, variable names): English. No exceptions, no mix.
- **Cleanup note.** `nanobot-setup.ps1` removes `$TMP_DIR` but preserves `$APP_DIR`. Don't re-enable the `$APP_DIR` Remove-Item.
- **No commit/push without explicit approval.** Never stage, commit, amend, or push unless the user explicitly requests it. Wait for a direct command.

## Upstream repo

`https://github.com/HKUDS/nanobot.git` branch `main`. Setup clones to `app/` (git) or downloads ZIP. The patches in `portable_paths.py` target upstream layout — if upstream refactors, check the patcher.
