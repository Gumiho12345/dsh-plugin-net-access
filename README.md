# dsh-plugin-net-access

[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

让 DSH 沙箱里的 `curl.exe` 能用 HTTPS，文件写保护不变。

DSH 的 Windows 沙箱会卡死所有走 Schannel 的 HTTPS（`0x8009030E`，平台限制，原因见 [docs/findings-zh.md](docs/findings-zh.md)）。本插件**不放松沙箱**，而是注入 OpenSSL 版 curl 绕开 Schannel。仅支持 DSH `0.1.0-rc.6`。

## 支持的功能

- [x] 沙箱内 `curl.exe` HTTPS 正常（PATH 注入 + `CURL_CA_BUNDLE`）
- [x] 文件写保护与 workspace-write 一致：工作区外（用户数据、C:\ 根目录）写入被拒
- [x] 权限选择器新增 **Net Access** 预设（盾牌+地球图标）
- [x] 一键安装脚本，自动下载 HTTPS 工具箱

## 安装

```powershell
.\setup.ps1
```

装完重启 DSH，浏览器硬刷新，左下角权限选择器选 **Net Access** 即可。

## 使用

```powershell
curl.exe -sS https://example.com                    # 200
Set-Content "$env:USERPROFILE\Desktop\t.txt" x      # 拒绝访问
New-Item -ItemType Directory C:\t                   # 拒绝访问
```

HTTPS 工具箱默认放在 `%USERPROFILE%\.dsh\netaccess-tools\bin\`，可用环境变量 `DSH_NETACCESS_TOOLBIN` 改位置。

## 常见问题

**为什么系统 curl / Invoke-WebRequest 还是不能用？**
它们走 Windows Schannel，而 Schannel 在受限令牌下无法工作。请用本插件注入的 `curl.exe`、python 或 node。

**C:\Users\Public 还能写？**
能。Everyone 是受限令牌必需的保活组，去掉进程无法启动。Public 是系统共享区，不影响你的数据。

**升级 DSH 后失效？**
补丁绑定 `0.1.0-rc.6`，升级后重新运行 `setup.ps1`；校验不匹配会中止并提示，不会静默覆盖。

## 卸载

```powershell
.\uninstall.ps1
```

## 许可

MIT。`patches/` 内含 `@deepseek-ai/dsh-*` 包（MIT，Copyright (c) 2026 DeepSeek）的修改后文件，保留其原始版权声明。
