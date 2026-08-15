# dsh-plugin-net-access

[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**DSH 的 net-access 权限模式：文件写保护和 workspace-write 一样严格，但沙箱里的 `curl.exe` 能用 HTTPS。**

DSH 的 Windows 沙箱（受限令牌）会卡死所有走 Schannel 的 HTTPS（报 `0x8009030E`）。本插件**不放松令牌**，而是由 runner 注入 OpenSSL 版 curl 绕开 Schannel。仅支持 `@deepseek-ai/dsh@0.1.0-rc.6`。

## 安装

前置：Windows + Node.js + DSH rc.6。

```sh
# 1. 权限预设（标准 dsh 插件安装）
dsh plugin add .\plugin

# 2. 引擎补丁（自动备份为 *.netaccess.bak + SHA256 校验）
.\install.ps1

# 3. HTTPS 工具箱：从 https://curl.se/windows/ 下载官方 win64 版 curl，
#    把 curl.exe 和 curl-ca-bundle.crt 放到：
#    %USERPROFILE%\.dsh\netaccess-tools\bin\
#    （或设环境变量 DSH_NETACCESS_TOOLBIN 指定其他目录）
```

重启 DSH（启动终端按 `Ctrl+C`，或 `netstat -ano | findstr 3080` 查进程号后 `taskkill /F /PID <pid>`，再 `npx @deepseek-ai/dsh web`），浏览器硬刷新，左下角权限选择器选 **Net Access**。

## 特性

- 写保护与 workspace-write 一致：工作区外（用户数据、C:\ 根目录）写入被拒
- `curl.exe` HTTPS 可用：PATH 注入 OpenSSL/LibreSSL 版 curl + `CURL_CA_BUNDLE`
- node / python 的 HTTPS 照常可用
- 权限选择器新增 Net Access 预设（盾牌+地球图标）

## 限制

- `C:\Users\Public` 挡不住（Everyone 是受限令牌必需的保活组）
- 系统 curl / Invoke-WebRequest（Schannel）仍不可用：用 OpenSSL 版 curl / python / node，或切 full access
- WMI 不可用（与 workspace-write 相同）
- 仅支持 rc.6：升级 DSH 后补丁失效，install.ps1 校验会提示，需重新对齐

## 验证

```powershell
curl.exe -sS https://example.com                    # 200
Set-Content "$env:USERPROFILE\Desktop\t.txt" x      # 拒绝访问
New-Item -ItemType Directory C:\t                   # 拒绝访问
```

## 卸载

```powershell
.\uninstall.ps1                  # 恢复引擎文件备份
dsh plugin remove dsh-plugin-net-access   # 移除预设（或手动还原 cordis.patch.yml）
```

## 目录结构

```
patches/            # 9 个打过补丁的引擎/客户端文件 + 预设补丁
plugin/             # 标准 dsh 插件包（预设部分）
install.ps1 / uninstall.ps1 / manifest.json
docs/findings-zh.md # 技术调查记录（令牌与 Schannel 的兼容性结论）
extras/             # dsh-launcher.ps1（可选后台启停启动器）
```

## 许可

MIT（见 [LICENSE](LICENSE)）。`patches/` 内含 `@deepseek-ai/dsh-*` 包（MIT，Copyright (c) 2026 DeepSeek）的修改后文件，保留其原始版权声明。
