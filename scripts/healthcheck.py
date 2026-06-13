#!/usr/bin/env python3
"""
Nanobot Portable - Health Check
Memeriksa kesiapan lingkungan setelah setup selesai.
Jalankan: python scripts/healthcheck.py [root_path]
"""

import sys
import os
from pathlib import Path


def get_root():
    """Dapatkan root path dari argument atau parent dari scripts/."""
    if len(sys.argv) > 1:
        return Path(sys.argv[1]).resolve()
    return Path(__file__).parent.parent.resolve()


def check_python_version(root):
    """Cek versi Python."""
    version = sys.version_info
    if version >= (3, 9):
        print(f"  [OK] Python {version.major}.{version.minor}.{version.micro}")
        return True
    else:
        print(f"  [WARN] Python {version.major}.{version.minor} - minimal 3.9+")
        return False


def check_nanobot_module():
    """Cek apakah modul nanobot terinstall."""
    try:
        import nanobot
        ver = getattr(nanobot, "__version__", "?")
        print(f"  [OK] Nanobot module: v{ver}")
        return True
    except ImportError:
        print("  [WARN] Nanobot module not installed. Run setup first.")
        return False


def check_config(root):
    """Cek konfigurasi."""
    config_file = root / "data" / "config.json"
    if config_file.exists():
        print(f"  [OK] config.json found")
        return True
    else:
        print(f"  [WARN] config.json not found")
        return False


def check_env(root):
    """Cek file .env."""
    env_file = root / "data" / ".env"
    if env_file.exists():
        content = env_file.read_text(encoding="utf-8", errors="ignore")
        if "sk-your-api-key" in content or "your-api-key" in content:
            print("  [WARN] API key still default. Edit data/.env first!")
            return False
        else:
            print("  [OK] .env configured")
            return True
    else:
        print("  [INFO] .env not found (create via edit_env.bat)")
        return False


def check_directories(root):
    """Cek direktori penting."""
    dirs = {
        "data":         root / "data",
        "knowledge":    root / "data" / "knowledge",
        "logs":         root / "data" / "logs",
        "home":         root / "data" / "home",
        "bin (python)": root / "bin",
        "git":          root / "bin" / "git",
    }

    all_ok = True
    for name, path in dirs.items():
        if path.exists():
            print(f"  [OK] {name}/")
        else:
            print(f"  [WARN] {name}/ not found")
            all_ok = False

    return all_ok


def check_lockhead(root):
    """Cek lockhead."""
    lf = root / "data" / ".lockhead"
    if lf.exists():
        print("  [OK] .lockhead present (setup completed)")
        return True
    else:
        print("  [INFO] .lockhead not found (setup not finalized)")
        return False


def main():
    root = get_root()
    print()
    print("  ================================================")
    print("       NANOBOT PORTABLE - HEALTH CHECK")
    print("  ================================================")
    print(f"   Root: {root}")
    print()

    results = []

    print("  Python")
    results.append(check_python_version(root))
    print()

    print("  Nanobot Module")
    results.append(check_nanobot_module())
    print()

    print("  Configuration")
    results.append(check_config(root))
    results.append(check_env(root))
    print()

    print("  Directories")
    results.append(check_directories(root))
    print()

    print("  Lockhead")
    results.append(check_lockhead(root))
    print()

    all_ok = all(results)
    if all_ok:
        print("  All checks passed! System ready to use.")
    else:
        if not results[2]:  # nanobot module missing
            print("  Warning: run nanobot-setup.ps1 to install.")
        elif not results[0]:  # python version
            print("  Python version too old. Update portable Python.")
        else:
            print("  Some checks need attention. Verify above.")

    print()
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
