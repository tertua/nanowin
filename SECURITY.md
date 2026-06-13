# Security Policy

## Supported Versions

| Version | Branch | Supported |
|---------|--------|-----------|
| Lite (latest) | `lite` | ✅ |
| Full | `main` | ✅ |

## Reporting a Vulnerability

Open an issue at https://github.com/tertua/nanobot-usb/issues

Do not open a public issue if the vulnerability exposes API keys or allows remote code execution. Use a private report instead.

## Security Features

### API Key Storage

- `.env` is encrypted to `.env.encrypted` using AES-256-GCM with scrypt key derivation.
- Plaintext `.env` is deleted immediately after encryption.
- Decrypted keys are stored in environment variables only — never written back to disk.

### Portable Isolation

- All paths are contained within the USB/installation directory.
- No system-wide Python, Node.js, or Git is required or modified.
- Temporary folders use `%TMP%` inside the portable root.

## Best Practices

- Delete `data/.env_key` after setup if you prefer interactive passphrase entry.
- Do not commit `data/.env`, `data/.env.encrypted`, `data/.env_key`, or `config.json` to version control.
- Review `requirements-lite.txt` before adding new dependencies.
- Run from a USB drive or isolated folder — not from a shared or public location.
