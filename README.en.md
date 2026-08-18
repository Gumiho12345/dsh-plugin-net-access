# dsh-plugin-net-access

[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/Gumiho12345/dsh-plugin-net-access?style=social&label=Star)](https://github.com/Gumiho12345/dsh-plugin-net-access/stargazers)
[![Awesome DSH Plugin](https://beancookie.github.io/awesome-dsh-plugin/badge.svg)](https://beancookie.github.io/awesome-dsh-plugin)
[![npm version](https://img.shields.io/npm/v/dsh-plugin-net-access.svg)](https://www.npmjs.com/package/dsh-plugin-net-access)

[简体中文](README.md) | English

A permission-mode patch for DSH: adds a **Net Access** mode that keeps the workspace-write file protection while restoring HTTPS inside the sandbox.

DSH's Windows sandbox (workspace-write) blocks Schannel-based HTTPS requests (error `0x8009030E`), so the built-in curl and Invoke-WebRequest don't work inside it. Net Access keeps the exact same file-write protection as workspace-write and makes HTTPS work again in the sandbox. Windows only; not pinned to a DSH version — the patches adapt by structural anchors.

## What it does

- `curl.exe` works with HTTPS inside the sandbox
- File-write protection identical to workspace-write: writes outside the workspace are denied
- A new **Net Access** option in the permission selector
- python / node HTTPS is unaffected

## How it works

The sandbox token stays exactly the same as workspace-write; the runner just prepends an OpenSSL-based curl to PATH so HTTPS no longer goes through the blocked Schannel. Full technical write-up: [docs/findings-zh.md](docs/findings-zh.md).

## Install

Option 1: via npm

```powershell
npx @deepseek-ai/dsh plugin --profile web add dsh-plugin-net-access
. "$env:USERPROFILE\.dsh\profiles\web\node_modules\dsh-plugin-net-access\setup.ps1"
```

Option 2: download from GitHub and run

```powershell
.\setup.ps1
```

`setup.ps1` does three things: patches the engine by structural anchors (not pinned to a DSH version), registers the permission preset, and downloads the OpenSSL curl toolbox from curl.se into `%USERPROFILE%\.dsh\netaccess-tools\bin\`.

**A full DSH restart is required for the plugin to load**: stop the 3080 listener (Ctrl+C in its terminal, or `netstat -ano | findstr 3080` + `taskkill /F /PID <pid>`), then run `npx @deepseek-ai/dsh web` again. Refreshing the browser alone will not load the new plugin. After the restart, refresh the page and pick **Net Access** in the permission selector (bottom-left).

**After a DSH upgrade**: just re-run `setup.ps1` — no need to wait for a plugin update, because the patches adapt by structural anchors instead of a version pin. If a future DSH restructure moves an anchor, the installer aborts with a clear error (nothing gets corrupted); update the plugin then.

## Verify

```powershell
curl.exe -sS https://example.com
# HTTP 200

Set-Content "$env:USERPROFILE\Desktop\t.txt" x
# access denied
```

## Known limitations

- The built-in curl and `Invoke-WebRequest` cannot use HTTPS: use the bundled `curl.exe`, python or node.
- git over HTTPS needs `git config --global http.sslBackend openssl` first.
- `C:\Users\Public` stays writable (same as workspace-write).
- WMI is unavailable (same as workspace-write).

## Uninstall

```powershell
.\uninstall.ps1
```

## License

MIT. Files under `patches/` come from the `@deepseek-ai/dsh-*` packages (MIT, Copyright (c) 2026 DeepSeek); keep their copyright notice when redistributing.

---

If you find this useful, a ⭐ Star would be appreciated.
