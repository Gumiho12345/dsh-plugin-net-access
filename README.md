# dsh-plugin-net-access

[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/Gumiho12345/dsh-plugin-net-access?style=social&label=Star)](https://github.com/Gumiho12345/dsh-plugin-net-access/stargazers)

[English](README.en.md) | 简体中文

DSH 的权限模式补丁：新增 **Net Access** 模式，在保持 workspace-write 文件写保护的基础上，恢复沙箱内的 HTTPS 访问。

DSH 的 Windows 沙箱（workspace-write）会拦截走 Schannel 的 HTTPS 请求（报 `0x8009030E`），系统自带的 curl 和 Invoke-WebRequest 都无法使用。Net Access 模式的文件写保护与 workspace-write 一致，同时让沙箱内的 HTTPS 恢复正常。仅支持 Windows、DSH `0.1.0-rc.6`。

## 作用

- 沙箱内 `curl.exe` 可正常访问 HTTPS
- 文件写保护与 workspace-write 一致：工作区外写入被拒
- 权限选择器新增 **Net Access** 选项
- python / node 的 HTTPS 不受影响

## 原理

保持 workspace-write 的沙箱令牌不变，只把 OpenSSL 版 curl 注入沙箱环境的 PATH，让 HTTPS 不再经过被拦截的 Schannel。完整技术说明见 [docs/findings-zh.md](docs/findings-zh.md)。

## 安装

```powershell
.\setup.ps1
```

这一条命令会做三件事：给引擎打补丁、注册权限预设、从 curl.se 自动下载 OpenSSL 版 curl 工具箱到 `%USERPROFILE%\.dsh\netaccess-tools\bin\`。

装完重启 DSH（`Ctrl+C` 停掉 3080 端口的进程再重新 `npx @deepseek-ai/dsh web`），刷新页面，在左下角权限选择器里选 **Net Access**。

## 验证

```powershell
curl.exe -sS https://example.com
# HTTP 200

Set-Content "$env:USERPROFILE\Desktop\t.txt" x
# 拒绝访问
```

## 已知限制

下面这些是机制决定的，不是配置问题：

- 系统自带的 curl 和 `Invoke-WebRequest` 依然不可用——它们走 Schannel，在受限令牌下无解。用本插件带的 `curl.exe`、python 或 node。
- git 的 HTTPS 也一样：沙箱内先执行 `git config --global http.sslBackend openssl` 切后端才能推送/拉取。
- `C:\Users\Public` 可写（workspace-write 同样如此）——`Everyone` 是受限令牌必需的保活组，去掉进程就起不来。
- WMI 不可用，和 workspace-write 一致。
- 补丁绑定 `0.1.0-rc.6`：升级 DSH 后需要重装。`setup.ps1` 会校验文件哈希，版本不匹配会直接中止、不会乱改。

## 卸载

```powershell
.\uninstall.ps1
```

## 许可

MIT。`patches/` 目录里的文件来自 `@deepseek-ai/dsh-*`（MIT，Copyright (c) 2026 DeepSeek），使用/分发时请保留相应署名。

---

觉得有用的话，欢迎点个 ⭐ Star 支持一下。
