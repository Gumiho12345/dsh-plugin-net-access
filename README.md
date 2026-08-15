# dsh-plugin-net-access

[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

DSH 的一个权限模式补丁：沙箱里能用 HTTPS 了。

DSH 的 Windows 沙箱有个坑：里面的 curl 访问 https 全部报 `0x8009030E`（走 Schannel 的都会被卡）。这个插件加了一个 net-access 模式，沙箱还是那个沙箱，只是把 OpenSSL 版的 curl 塞进 PATH，HTTPS 就能用了。

仅支持 DSH `0.1.0-rc.6`。

## 做什么

- 沙箱里 `curl.exe` 能访问 HTTPS（自动注入 OpenSSL 版 curl）
- 文件写保护不变：工作区外照样写不进去
- 权限选择器多一个 Net Access 选项（盾牌+地球图标）
- 一条命令装完，工具箱自动下载

## 安装

```powershell
.\setup.ps1
```

装完重启 DSH，刷新页面，左下角权限选择器选 **Net Access**。

## 验证

```powershell
curl.exe -sS https://example.com
# HTTP 200

Set-Content "$env:USERPROFILE\Desktop\t.txt" x
# 拒绝访问
```

## 已知问题

- 系统自带的 curl 和 Invoke-WebRequest 还是不能用（它们走 Schannel，这个沙箱机制下无解）；用本插件带的 `curl.exe`、python 或 node
- `C:\Users\Public` 依然可写（Everyone 是沙箱必需的保活组，去不掉）
- 绑定 rc.6：升级 DSH 后需要重装，setup.ps1 会校验，不匹配会中止
- WMI 不可用（和 workspace-write 一样）

## 卸载

```powershell
.\uninstall.ps1
```

## 许可

MIT。`patches/` 里的文件来自 `@deepseek-ai/dsh-*`（MIT，Copyright (c) 2026 DeepSeek）。
