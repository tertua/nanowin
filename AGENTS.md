# AGENTS.md — nanowin

Windows-portable runtime for [tertua/nanobot](https://github.com/tertua/nanobot) (a fork of HKUDS/nanobot). Runs on built-in Windows PowerShell 5.1+ (no PS7). Everything lives on a USB drive; touches zero host state.

- No test runner, linter, type checker, or CI.
- `setup.bat` fetches portable Python/Node/Git/gh into `bin/`. No host tools required.
- Chat output to user: formal Indonesian. Everything else (code, comments, docs, logs, variable names): English.

## Commands (run from repo root on Windows)

| Command | Action |
|---|---|
| `setup.bat` | One-shot install. Delete `data\.lockhead` to re-run. |
| `edit_env.bat` | Decrypt `.env.encrypted` → notepad → re-encrypt. |
| `start-chat.bat` | CLI chat via `scripts\nanobot-agent.ps1`. |
| `start-gateway.bat` | Web gateway (WebUI :8765, HTTP/API :8900). Kills stale listeners on the ports at startup; releases ports on `PowerShell.Exiting`. |
| `build-webui.bat` | `npm install` + build in `app\webui`, copy to `bin\Lib\site-packages\nanobot\web\dist\`. Run **after every** `setup.bat` — Lite skips webui builds. |
| `bin\python.exe scripts\healthcheck.py` | Post-install verification. |

Setup log: `setup_log.txt`. Runtime logs: `data\logs\nanobot_YYYY-MM-DD.log`.

## Architecture

```
setup.bat → .bat wrappers → powershell -File .ps1

scripts/
  nanobot-setup.ps1    # Orchestrator: dot-sources setup/*.ps1 in order
  nanobot-agent.ps1    # CLI launcher
  nanobot-gateway.ps1  # Gateway launcher (kills stale ports on startup, registers PowerShell.Exiting)
  init_portable.ps1    # Dot-sourced by every .ps1. Relaunches under Bypass if policy is
                       # Restricted/AllSigned. Redirects USERPROFILE/HOME/HOMEPATH/TEMP/TMP/
                       # APPDATA/LOCALAPPDATA → data/. Sets GH_CONFIG_DIR, PIP_CACHE_DIR,
                       # NPM_CONFIG_CACHE, NPM_CONFIG_PREFIX. Builds $PortablePaths and
                       # prepends to $env:PATH. Creates .nanowin marker file (the nanobot
                       # fork detects the portable root via this + data/config.json).
                       # Exports Load-EnvEncrypted (AES-GCM scrypt loader) and Resolve-Workspace.
  env_crypt.py         # AES-256-GCM + scrypt (encrypt/decrypt/load). --noninteractive uses NANOBOT_ENV_KEY.
  post_config.py       # Post-processes nanobot onboard config: adds custom/nvidia/aihubmix
                       # providers w/ ${VAR} refs, CLI channel, restrictToWorkspace, and
                       # sync_env_template() to keep .env in step with config references.
  lockhead.py          # Writes .lockhead INI with [system] + [software] sections (host
                       # metadata + portable tool versions). Preserves unknown sections.
  resolve_workspace.py # Reads workspace path from config.json; called by agent/gateway launchers.
  requirements-lite.txt # Pip dependency manifest. No pyproject.toml extras.
  install_webui.ps1    # npm install + build, copy into bin/Lib/site-packages/nanobot/web/dist/.
                       # Uses npm only (bun's HOME-relative store breaks on exFAT/FAT32).
                       # Runs npm --ignore-scripts then manually invokes esbuild install.js.
  sync_webui.ps1       # Manual drop-zone workflow: copies data/webui/ into site-packages.
                       # NOT called by build-webui.bat — that's a separate direct path.
  edit_env_helper.ps1  # Shows provider context during edit_env.bat flow.
  healthcheck.py, lockhead.py, unzip.vbs
  setup/               # Dot-sourced by nanobot-setup.ps1 in order:
    install_busybox.ps1 → install_python.ps1 → install_git.ps1 → install_gh.ps1 → install_nodejs.ps1
    → install_source.ps1 → install_deps.ps1
    setup_helpers.ps1    # Write-OK, Write-Step, Download-Helper, Extract-Helper, Verify-Hash
    download.ps1         # 3-method fallback
    extract.ps1          # 4-method fallback

app/   # Upstream nanobot source (gitignored). Git clone preferred — ZIP lacks app/webui/.
bin/   # Portable BusyBox, Python embed, MinGit, Node.js, gh (gitignored).
data/  # config.json, .env / .env.encrypted / .env_key / .env.tmp, .lockhead,
       # knowledge/, logs/, workspace/, webui/ drop zone (gitignored).
.nanowin       # Empty marker file. The fork's nanobot/config/portable.py uses
               # (this + data/config.json) to detect the portable install root.
```

## Critical conventions

- **Whitelist `.gitignore`.** Starts with `/*` — add `!/path` for new tracked files. Tracked: `setup.bat`, `start-chat.bat`, `edit_env.bat`, `build-webui.bat`, `start-gateway.bat`, `scripts/**`, `README.md`, `SECURITY.md`, `AGENTS.md`, `LICENSE`, `.github/`, `.github/FUNDING.yml`, `.gitattributes`, `.gitignore`.
- **Line endings.** `.ps1`/`.bat`/`.vbs`/`.cmd` are CRLF (PS5.1 chokes on LF). `.py`/`.md`/`.json`/`.yml`/`.toml`/`.txt` are LF.
- **Hard-coded versions** in `scripts/nanobot-setup.ps1` (`$PyVer=3.12.3`, `$GitVer=2.55.0`, `$NodeVer=26.8.1`, `$GhVer=2.100.0`). Bump there — no manifest. **When bumping a version, also update its SHA-256 hash** in the corresponding `install_*.ps1` script (hash tables keyed by arch). Compute via: `curl -sL <url> | sha256sum` (Linux) or `Get-FileHash` (Windows).
- **BusyBox single EXE** from `frippery.org/files/busybox/` (x64 only — `busybox64.exe`). No archive; `Download-Helper` saves to `bin\busybox.exe`, then copies to `bin\sh.exe`. Hash: `07bb1e5b095b00d68a695481f9240879f33c5724b40aa2308f999d54ed78f075`.
- **Python embed `.pth` patching** (`setup/install_python.ps1`): uncomments `import site`, appends `Lib`, `Lib\site-packages`, `..\app`. Without this, pip and app/ imports fail.
- **Lite skips webui builds.** `setup/install_deps.ps1` sets `$env:NANOBOT_SKIP_WEBUI_BUILD=1` before `pip install --no-deps $APP_DIR`, so the upstream hatch hook never builds `nanobot\web\dist\`. Always run `build-webui.bat` after `setup.bat`. `sync_webui.ps1` is the manual alternative if you already built into `data\webui/`.
- **Upstream ZIP install** does not include `app/webui/`. Only `git clone` does. `build-webui.bat` checks for `app\webui\package.json` and fails early with a clear message.
- **`.env` encrypted at rest** (AES-256-GCM + scrypt). `edit_env.bat` is the only plaintext path. Launchers use `Load-EnvEncrypted` → `env_crypt.py load` → `.env.tmp` → process env → delete `.env.tmp`. Never commit a key.
- **`data\.env_key`** makes launchers non-interactive. Delete to force an interactive passphrase prompt.
- **`data\.lockhead`** = setup-done sentinel (INI file). Short-circuits `nanobot-setup.ps1`. Delete to reset. Contains `[system]` + `[software]` sections (host metadata + tool versions); other sections are preserved across re-runs.
- **Portable root detection** lives in the nanobot fork (`nanobot/config/portable.py`), driven by `.nanowin` + `data/config.json`. Do **not** set `NANOBOT_HOME` / `NANOBOT_WORKSPACE` env vars — `init_portable.ps1` does not export them (deliberate; see comment at scripts/init_portable.ps1:142).
- **New launchers must** define `$ROOT` via `$DATA_DIR` etc. (or get them by dot-sourcing `scripts/init_portable.ps1`), call `Load-EnvEncrypted`, and call `Resolve-Workspace` if workspace path matters. Don't inline these.
- **Default config** (`post_config.py`): `model: openai/gpt-oss-120b`, `provider: nvidia`, `disabledSkills: ["summarize", "tmux"]` (Windows-incompatible upstream skills), `restrictToWorkspace: true` (at `tools` level, **not** `tools.exec` — `ExecToolConfig` doesn't have that field). Also registers `custom` (uses `${NANOBOT_CUSTOM_API_KEY}` + `${NANOBOT_CUSTOM_API_BASE}`), `nvidia` (`${NVIDIA_NIM_API_KEY}`), and `aihubmix` (`${AIHUBMIX_API_KEY}`) providers. `pathAppend` left empty — PATH inherited from parent process (correct regardless of USB drive letter / workspace location).
- **Gateway ports.** WebUI/WS on `:8765`, HTTP/API on `:8900` (`/v1/chat/completions`, `/v1/models`). External tools use `:8900` as OpenAI API base. Ports are read from `config.json` (`api.port`, `channels.websocket.port/host`) with `8900` / `8765` / `127.0.0.1` as defaults.
- **`sync_env_template`** (`post_config.py`): walks `config.json` for `${VAR}` refs and ensures `data\.env` has a matching `VAR=null` line for each missing key. Never overwrites existing values. Run by `setup.bat` only — manual edits to `.env` survive but new `${VAR}` refs in config won't auto-add unless you re-run setup or post_config.
- **OpenAI SDK emoji patch.** `setup/install_deps.ps1` patches `openai/_utils/_json.py`: `ensure_ascii=False` → `True`, appends `errors='replace'` to `.encode()`. Idempotent; backup at `_json.py.backup`.
- **`pip install --no-deps $APP_DIR`** installs the nanobot package without re-resolving deps. Combined with `NANOBOT_SKIP_WEBUI_BUILD=1`, this is the reason `build-webui.bat` is a separate step.
- **npm only for webui builds.** Bun's HOME-relative package store (`~/.bun/install/cache`) breaks on exFAT/FAT32 (`MoveFileEx` → `EINVAL`). `bun --no-cache` only skips the manifest cache, not the package store, and there's no env override. npm's flat `node_modules/` works on any filesystem.
- **esbuild EFTYPE on USB.** `install_webui.ps1` runs `npm install --ignore-scripts`, then manually invokes `esbuild/install.js`. The postinstall validation binary may fail (`EFTYPE` on FAT32/exFAT) but a cached binary from a prior run still works. Treated as `[WARN]`, not a hard failure.
- **`.bat` files are thin wrappers** — check `where powershell`, call `.ps1` with `-NoProfile -ExecutionPolicy Bypass`, `pause` on error. Don't edit for logic.
- **Cleanup note.** `nanobot-setup.ps1` removes `$TMP_DIR` but preserves `$APP_DIR`. Don't re-enable the `$APP_DIR` `Remove-Item`.
- **No commit/push without explicit approval.** Never stage, commit, amend, or push unless the user explicitly requests it. Wait for a direct command.

## Source repo

Setup clones `https://github.com/tertua/nanobot.git` branch `master` (a fork of HKUDS/nanobot). Falls back to ZIP download from the same repo. Portability now lives inside the fork (`nanobot/config/portable.py`) — if upstream refactors that path, check that the `.nanowin` marker + `data/config.json` detection still resolves correctly.
