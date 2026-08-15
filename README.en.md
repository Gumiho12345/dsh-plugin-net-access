# dsh-plugin-net-access

[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/Gumiho12345/dsh-plugin-net-access?style=social&label=Star)](https://github.com/Gumiho12345/dsh-plugin-net-access/stargazers)

[简体中文](README.md) | English

A permission-mode patch for DSH: adds a **Net Access** mode that keeps the workspace-write file protection while restoring HTTPS inside the sandbox.

DSH's Windows sandbox (workspace-write) blocks Schannel-based HTTPS requests (error `0x8009030E`), so the built-in curl and Invoke-WebRequest don't work inside it. Net Access keeps the exact same file-write protection as workspace-write and makes HTTPS work again in the sandbox. Windows + DSH `0.1.0-rc.6` only.

## What it does

- `curl.exe` works with HTTPS inside the sandbox
- File-write protection identical to workspace-write: writes outside the workspace are denied
- A new **Net Access** option in the permission selector
- python / node HTTPS is unaffected

## How it works

The sandbox token stays exactly the same as workspace-write; the runner just prepends an OpenSSL-based curl to PATH so HTTPS no longer goes through the blocked Schannel. Full technical write-up: [docs/findings-zh.md](docs/findings-zh.md).

## Install

```powershell
.\setup.ps1
```

This one command does three things: patches the engine, registers the permission preset, and downloads the OpenSSL curl toolbox from curl.se into `%USERPROFILE%\.dsh\netaccess-tools\bin\`.

Restart DSH (Ctrl+C in its terminal, or find the 3080 listener with `netstat -ano | findstr 3080` and `taskkill /F /PID <pid>`, then `npx @deepseek-ai/dsh web`), refresh the page, and pick **Net Access** in the permission selector (bottom-left).

## Verify

```powershell
curl.exe -sS https://example.com
# HTTP 200

Set-Content "$env:USERPROFILE\Desktop\t.txt" x
# access denied
```

## Known limitations

These come from the mechanism, not from configuration:

- The built-in curl and `Invoke-WebRequest` still don't work — they use Schannel, which cannot work under a restricted token. Use the bundled `curl.exe`, python or node.
- `C:\Users\Public` stays writable (same as workspace-write) — `Everyone` is a mandatory keep-alive group of the restricted token; removing it stops the process from starting.
- WMI is unavailable, same as workspace-write.
- Pinned to `0.1.0-rc.6`: reinstalling is needed after a DSH upgrade. `setup.ps1` verifies file hashes and aborts on mismatch instead of silently overwriting anything.

## Uninstall

```powershell
.\uninstall.ps1
```

## License

MIT. Files under `patches/` come from the `@deepseek-ai/dsh-*` packages (MIT, Copyright (c) 2026 DeepSeek); keep their copyright notice when redistributing.

---

If you find this useful, a ⭐ Star would be appreciated.
