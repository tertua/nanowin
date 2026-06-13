"""Password-based .env encryption for Nanobot Portable.

DO NOT hardcode API KEY on config.json

AES-256-GCM with scrypt key derivation — fully portable across Windows
machines. No dependency on DPAPI, TPM, or Windows user identity.

Security: OWASP 2023 scrypt parameters (N=1<<20, r=8, p=1).

Usage:
    python scripts/env_crypt.py encrypt                 # prompt passphrase + lock
    python scripts/env_crypt.py encrypt --save-key      # after lock, offer to save passphrase
    python scripts/env_crypt.py load                    # prompt passphrase -> .env.tmp
    python scripts/env_crypt.py load --noninteractive   # use NANOBOT_ENV_KEY env var
    python scripts/env_crypt.py decrypt                 # prompt passphrase -> .env (edit)
"""

import os, sys, base64, json, logging
from getpass import getpass
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
from cryptography.exceptions import InvalidTag

_KEY_LEN = 32
_NONCE_LEN = 12
_SALT_LEN = 32
_SCRYPT_N = 1 << 20
_SCRYPT_R = 8
_SCRYPT_P = 1
_VERSION = 2
_PASSPHRASE_ENV = "NANOBOT_ENV_KEY"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_PATH = os.path.join(ROOT, "data", ".env")
ENCRYPTED_PATH = ENV_PATH + ".encrypted"
TMP_PATH = os.path.join(ROOT, "data", ".env.tmp")
KEY_PATH = os.path.join(ROOT, "data", ".env_key")
LOG_DIR = os.path.join(ROOT, "data", "logs")
LOG_PATH = os.path.join(LOG_DIR, "encrypt.log")

_log = logging.getLogger("env_crypt")

def _init_log() -> None:
    os.makedirs(LOG_DIR, exist_ok=True)
    h = logging.FileHandler(LOG_PATH, encoding="utf-8", mode="a")
    h.setFormatter(logging.Formatter("%(asctime)s | %(levelname)-8s | %(message)s"))
    _log.addHandler(h)
    _log.setLevel(logging.INFO)

def _get_passphrase(prompt: str = "Passphrase") -> str:
    if "--noninteractive" in sys.argv:
        pwd = os.environ.get(_PASSPHRASE_ENV)
        if not pwd:
            _log.error("Non-interactive mode requires a configured passphrase environment variable")
            sys.exit(1)
        return pwd
    return getpass(f"  [{prompt}] ")

def _prompt_yes_no(prompt: str, default_yes: bool = False) -> bool:
    """Prompt user for yes/no. Returns True only on explicit y/yes."""
    suffix = "[Y/n]" if default_yes else "[y/N]"
    try:
        resp = input(f"  {prompt} {suffix} ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        return False
    if not resp:
        return default_yes
    return resp in ("y", "yes")

def _maybe_save_key(passphrase: str) -> None:
    """Offer to persist passphrase to data/.env_key for non-interactive launches."""
    if os.path.exists(KEY_PATH):
        prompt_text = "data/.env_key already exists. Overwrite?"
    else:
        print("  [INFO] Storing .env_key makes the launcher non-interactive.")
        print("         OK if: USB always with you (scheduled tasks, demos, screen-share).")
        print("         Risk: physical theft of USB = instant-decrypt of .env.encrypted")
        print("         (scrypt brute-force protection is bypassed when .env_key exists).")
        prompt_text = "Save passphrase to data/.env_key?"
    if not _prompt_yes_no(prompt_text, default_yes=False):
        print("  [SKIP] .env_key not modified.")
        _log.info("save-key: declined")
        return
    os.makedirs(os.path.dirname(KEY_PATH), exist_ok=True)
    tmp = KEY_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(passphrase + "\n")
    os.replace(tmp, KEY_PATH)
    _log.info("save-key: success -> %s", os.path.relpath(KEY_PATH, ROOT))
    print("  [DONE] Passphrase saved to data/.env_key")
    print("  [INFO] Delete this file to force interactive passphrase prompts.")

def _derive_key(passphrase: str, salt: bytes) -> bytes:
    kdf = Scrypt(salt=salt, length=_KEY_LEN, n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P)
    return kdf.derive(passphrase.encode("utf-8"))

def _encrypt(plaintext: bytes, passphrase: str) -> bytes:
    salt = os.urandom(_SALT_LEN)
    key = _derive_key(passphrase, salt)
    nonce = os.urandom(_NONCE_LEN)
    aesgcm = AESGCM(key)
    ct_and_tag = aesgcm.encrypt(nonce, plaintext, None)
    ct = ct_and_tag[:len(ct_and_tag)-16]
    tag = ct_and_tag[len(ct_and_tag)-16:]
    payload = {
        "v": _VERSION,
        "salt": base64.b64encode(salt).decode("ascii"),
        "nonce": base64.b64encode(nonce).decode("ascii"),
        "tag": base64.b64encode(tag).decode("ascii"),
        "ct": base64.b64encode(ct).decode("ascii"),
    }
    return json.dumps(payload, separators=(",", ":")).encode("ascii")

def _decrypt(ciphertext: bytes, passphrase: str) -> bytes:
    payload = json.loads(ciphertext.decode("ascii"))
    if payload.get("v") != _VERSION:
        raise ValueError(f"Unsupported version: {payload.get('v')}")
    salt = base64.b64decode(payload["salt"])
    nonce = base64.b64decode(payload["nonce"])
    tag = base64.b64decode(payload["tag"])
    ct = base64.b64decode(payload["ct"])
    key = _derive_key(passphrase, salt)
    aesgcm = AESGCM(key)
    return aesgcm.decrypt(nonce, ct + tag, None)

def cmd_encrypt() -> None:
    _init_log()
    _log.info("encrypt: start")
    if not os.path.exists(ENV_PATH):
        print("  [SKIP] .env not found.")
        _log.info("encrypt: skipped (no .env)")
        return
    passphrase = _get_passphrase("Enter passphrase for encryption")
    with open(ENV_PATH, "rb") as f:
        plaintext = f.read()
    ciphertext = _encrypt(plaintext, passphrase)
    # Atomic write: temp file + rename to prevent partial/corrupt writes
    # and bypass read-only flag on existing .env.encrypted
    tmp = ENCRYPTED_PATH + ".tmp"
    with open(tmp, "wb") as f:
        f.write(ciphertext)
    os.replace(tmp, ENCRYPTED_PATH)
    os.remove(ENV_PATH)
    _log.info("encrypt: success -> %s", os.path.relpath(ENCRYPTED_PATH, ROOT))
    print("  [DONE] Encrypted .env secrets -> data/.env.encrypted")
    print("  [INFO] The original .env file has been deleted.")
    if "--save-key" in sys.argv and sys.stdin.isatty():
        _maybe_save_key(passphrase)

def cmd_load() -> None:
    _init_log()
    _log.info("load: start")
    if not os.path.exists(ENCRYPTED_PATH):
        print("  [SKIP] .env.encrypted nto found.", file=sys.stderr)
        _log.warning("load: skipped")
        return
    passphrase = _get_passphrase("Enter passphrase for decryption")
    with open(ENCRYPTED_PATH, "rb") as f:
        ciphertext = f.read()
    try:
        plaintext = _decrypt(ciphertext, passphrase)
    except InvalidTag:
        _log.warning("load: decryption failed (invalid passphrase or corrupted file)")
        print("  [ERROR] Incorrect passphrase or corrupted .env.encrypted file.", file=sys.stderr)
        sys.exit(1)
    with open(TMP_PATH, "w", encoding="utf-8") as f:
        for line in plaintext.decode("utf-8").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            f.write(stripped + "\n")
    _log.info("load: success -> %s", os.path.relpath(TMP_PATH, ROOT))
    print("  [DONE] .env.encrypted decrypted -> data/.env.tmp")
    print("  [INFO] .env.tmp will be deleted after loading the script.")

def cmd_decrypt() -> None:
    _init_log()
    _log.info("decrypt: start")
    if not os.path.exists(ENCRYPTED_PATH):
        print("  [SKIP] .env.encrypted not found.", file=sys.stderr)
        _log.warning("decrypt: skipped")
        return
    passphrase = _get_passphrase("Enter passphrase for decryption")
    with open(ENCRYPTED_PATH, "rb") as f:
        ciphertext = f.read()
    try:
        plaintext = _decrypt(ciphertext, passphrase)
    except InvalidTag:
        _log.warning("decrypt: decryption failed (invalid passphrase or corrupted file)")
        print("  [ERROR] Incorrect passphrase or corrupted .env.encrypted file.", file=sys.stderr)
        sys.exit(1)
    with open(ENV_PATH, "wb") as f:
        f.write(plaintext)
    _log.info("decrypt: success -> %s", os.path.relpath(ENV_PATH, ROOT))
    print("  [DONE] .env.encrypted decrypted -> data/.env")
    print("  [INFO] Edit .env, then run 'encrypt' to re-lock.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "encrypt":
        cmd_encrypt()
    elif cmd == "load":
        cmd_load()
    elif cmd == "decrypt":
        cmd_decrypt()
    else:
        print(f"  [ERROR] Unknown command: {cmd}")
        sys.exit(1)
