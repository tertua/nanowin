# AGENTS.md — nanowin

Windows-portable runtime for [HKUDS/nanobot](https://github.com/HKUDS/nanobot). "Lite" edition runs on built-in Windows PowerShell 5.1+; no PowerShell 7 required. Everything lives on a USB drive and touches zero host state.

- Windows 10 1809+ (64-bit). No package manifest, CI, test runner, linter, or type checker.
- No host Python/Node/Git/gh — `setup.bat` fetches portable versions into `bin/`.

## Commands (from repo root on Windows)

| Command | Action |
|---|---|---|
| `setup.bat` | One-shot install. Short-circuits if `data\.lockhead` exists — delete it to re-run. |
| `edit_env.bat` | Decrypt `data\.env.encrypted` → notepad → re-encrypt (saves key on first encrypt). |
| `start-chat.bat` | Launch CLI chat (`scripts\nanobot-agent.ps1` wrapper). |
| `start-gateway.bat` | Launch web gateway (`scripts\nanobot-gateway.ps1` wrapper, WebUI :8765, API :8900). |
| `build-webui.bat` | `npm install + build` in `app\webui`, then copy to site-packages (`scripts\install_webui.ps1`). |
| `bin\busybox.exe --help` | List available BusyBox applets (100+ Unix commands). |
| `bin\python.exe scripts\healthcheck.py` | Post-install verification. |
| `& $PY -m nanobot agent` / `& $PY -m nanobot gateway` | Nanobot is invoked as a Python module, not a CLI binary (from `scripts\nanobot-agent.ps1` / `scripts\nanobot-gateway.ps1`). |

Setup log: `setup_log.txt`. Runtime logs: `data\logs\nanobot_YYYY-MM-DD.log`.

## Architecture

```
setup.bat ←→ .bat files  # Batch wrappers; enforce Win10+ and PS5.1+, call powershell -File ...
scripts/
  nanobot-setup.ps1   # Orchestrator: dot-sources setup/*.ps1 in order:
                      #   BusyBox → Python → Git → gh → Node.js → source → pip deps → config
  nanobot-agent.ps1   # CLI launcher (dot-sources init_portable.ps1, loads .env, runs python -m nanobot agent)
  nanobot-gateway.ps1 # Gateway launcher (same pattern, reads ports from config.json, kills stale processes on startup)
  init_portable.ps1   # Dot-sourced by all .ps1 launchers. Redirects USERPROFILE/HOME/TEMP/APPDATA/LOCALAPPDATA to data/.
                      # Sets NANOBOT_HOME, GH_CONFIG_DIR, PIP_CACHE_DIR, NPM_CONFIG_CACHE, NPM_CONFIG_PREFIX, builds $PortablePaths.
                      # Exports Load-EnvEncrypted function (decrypts .env.encrypted → process env vars → deletes .env.tmp).
  env_crypt.py        # AES-256-GCM + scrypt (encrypt/load/decrypt). --noninteractive uses NANOBOT_ENV_KEY env var.
  portable_paths.py   # Patches upstream nanobot source paths to never use ~/.nanobot.
                      # Targets: paths.py, loader.py, schema.py, cli/commands.py (log handlers,
                      # multiline input), utils/helpers.py (custom workspace templates).
  post_config.py      # Post-processes `nanobot onboard` config: adds custom provider with ${VAR} refs, CLI+WS channels,
                      # merges disabledSkills, sets tools.restrictToWorkspace, syncs .env template.
  resolve_workspace.py  # Reads workspace path from config.json; called by agent/gateway launchers.
  requirements-lite.txt # Pip dependency manifest (no pyproject.toml extras).
  write_lockhead.py, healthcheck.py, unzip.vbs
  setup/              # Dot-sourced by nanobot-setup.ps1 in this order:
    install_busybox.ps1 → install_python.ps1 → install_git.ps1 → install_gh.ps1 → install_nodejs.ps1
    → install_source.ps1 → install_deps.ps1
    setup_helpers.ps1  # Write-OK, Write-Step, Download-Helper, Extract-Helper
    download.ps1       # 3-method fallback: Invoke-WebRequest → WebClient → HttpClient
    extract.ps1        # 4-method fallback: Expand-Archive → COM → .NET ZipFile → VBS cscript
app/    # Cloned/extracted upstream nanobot source (gitignored)
bin/    # Portable BusyBox, Python, MinGit, Node.js, gh (gitignored)
data/   # Runtime data: config.json, .env.encrypted, .env_key, .lockhead, knowledge/, logs/, workspace/ (gitignored)
```

## Critical conventions

- **Whitelist `.gitignore`.** Starts with `/*` — any new top-level file needs a `!/path` rule. Tracked set: `setup.bat`, `start-chat.bat`, `edit_env.bat`, `build-webui.bat`, `start-gateway.vbs`, `scripts/**`, `README.md`, `SECURITY.md`, `AGENTS.md`, `LICENSE`, `.github/`, `.gitattributes`, `.gitignore`.
- **Line endings.** `.ps1`/`.bat`/`.vbs`/etc. are CRLF (PS5.1 chokes on LF). `.py`/`.md`/`.json`/etc. are LF.
- **Hard-coded versions in `nanobot-setup.ps1`** (`$PyVer`, `$GitVer`, `$NodeVer`, `$ArchPython`, `$ArchNode`, `$ArchMinGit`, `$MinGwDir`). Bump them there — no manifest. BusyBox has no version variable — always downloads the latest from frippery.org (no versioned releases).
- **BusyBox is a single EXE download** from `https://frippery.org/files/busybox/`. No archive extraction; `Download-Helper` saves directly to `bin\busybox.exe`. `install_busybox.ps1` is the first install step so its tools are available for subsequent setup steps.
- **Python embed `.pth` patching.** `install_python.ps1` uncomments `#import site` and appends `Lib`, `Lib\site-packages`, `..\app` to the `._pth` file. Without this, pip and `app/` imports fail.
- **`.env` encrypted at rest.** `edit_env.bat` is the only path to plaintext (decrypt→notepad→re-encrypt). Launchers use `Load-EnvEncrypted` → `env_crypt.py load` → `.env.tmp` → process env → delete `.env.tmp`. Never write a real key into a tracked file.
- **`data\.env_key` (optional stored passphrase)** makes launcher non-interactive. Delete it to force interactive prompt. Risk: physical USB theft = instant decrypt.
- **`data\.lockhead`** = setup-done sentinel (INI file with `[system]` + `[software]` sections + preserved non-managed sections like `[sha]`). Short-circuits `nanobot-setup.ps1`. Delete it to reset.
- **`NANOBOT_HOME`** env var overrides `~/.nanobot` for config. Set in `init_portable.ps1` to `data/`.
- **New launchers must** define `$ROOT`, then dot-source `scripts/init_portable.ps1` (atau `$ROOT/../init_portable.ps1` jika di subdir), then call `Load-EnvEncrypted`. Don't reimplement.
- **Default config** (`post_config.py`): `model: sengkuni-1.0`, `provider: custom` (uses `${NANOBOT_CUSTOM_API_KEY}` + `${NANOBOT_CUSTOM_API_BASE}`), `disabledSkills: ["summarize", "tmux"]`, `tools.restrictToWorkspace: true`. `tools.exec.pathAppend` is left empty — `_build_env()` inherits PATH from parent (launcher prepends `$PortablePaths`), which is correct regardless of USB drive letter or workspace location. Absolute `pathAppend` would break on drive letter changes; relative would break if workspace moves outside root.
- **Gateway ports** WebUI/WS on :8765, OpenAI-compatible API on :8900 (`/v1/chat/completions`, `/v1/models`, etc.). External tools (e.g. opencode) use `:8900` as an OpenAI API base URL. `nanobot-gateway.ps1` reads both ports from `config.json` and passes `--port` (API) to CLI; the WS port is picked up by the gateway from config at runtime. Silently kills stale processes on both ports at startup and registers a `PowerShell.Exiting` handler.
- **Custom workspace templates** (`scripts/templates/`). `portable_paths.py` patches `utils/helpers.py` → `sync_workspace_templates()` to check `{NANOBOT_HOME}/../scripts/templates/` before falling back to upstream bundled templates. Edit these `.md` files to control what nanobot writes to a new workspace on first run. Deleted custom templates directory → silently falls back to upstream defaults, no crash.
- **Patches upstream source.** `portable_paths.py` rewrites `paths.py`, `loader.py`, `schema.py`, `cli/commands.py`, `utils/helpers.py`. Logs `[WARN] pattern not found` for misses — re-check after upstream bump. The `commands.py` log-handler patch is post-condition-checked (sentinels: `logger.remove()` + `"DEBUG" if X else "INFO"` + `level="DEBUG", rotation="1 day"`).
- **`pip install --no-deps`** wipes the webui `dist/`. Re-run `build-webui.bat` or `sync-webui.bat` after every `setup.bat`.
- **Upstream ZIP install** does not include `app/webui/`. Only git clone does. `build-webui.bat` checks for `app\webui\package.json` and fails early.
- **npm only for webui builds.** Bun's HOME-relative package store breaks on exFAT/FAT32. npm's flat `node_modules/` works on any filesystem.
- **`.bat` files are thin wrappers** — they check `where powershell`, call the `.ps1` script, and pause on error. Don't edit them for logic changes.
- **Indonesian/English mixed strings** in `setup.bat:91` and elsewhere are intentional. Don't "fix" them.
- **Language rule.** Chat output to user: formal Indonesian. Everything else (code, comments, commit messages, file content, docs, variable names, logs): English. No exceptions, no mix.
- `nanobot-setup.ps1` comment says "Cleanup skipped — app/ and tmp/ preserved for inspection" but `$TMP_DIR` IS removed. `$APP_DIR` stays. Don't re-enable the `$APP_DIR` Remove-Item.
- **`lite`** branch is the active development branch. `master` / `main` target different toolchain assumptions.


## AI agent instructions

- **AGENTS.md is the agent's memory — README.md is for humans.** AI agents must treat AGENTS.md as the authoritative source of project structure, conventions, and decisions. README.md may be incomplete or misleading. All critical context goes here, not in README.

## Upstream repo

`https://github.com/HKUDS/nanobot.git` branch `main`. Setup clones to `app/` (git) or downloads ZIP. The patches in `portable_paths.py` target upstream layout — if upstream refactors, check the patcher.
