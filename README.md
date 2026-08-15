# dsh-plugin-net-access

DeepSeek Harness (DSH) **Net Access** 权限模式 v2：**文件写保护与 workspace-write 完全一致（严格）**，同时通过"网络工具箱注入"让沙箱内的 `curl.exe` HTTPS 可用。

> 状态：为 `@deepseek-ai/dsh 0.1.0-rc.6`（Windows）制作。核心引擎改动以补丁包形式提供（rc.6 模式词汇表编译期闭合，纯配置插件无法扩展）；预设部分同时提供标准 dsh 插件形态（`plugin/`）。

## v2 设计（相对 v1 的修正）

v1 为恢复 WMI 而把 Authenticated Users/INTERACTIVE 加进了限制 SID 列表，代价是 **C:\ 根目录与 C:\Users\Public 重新可写**（实测确认），且 Schannel HTTPS 依然不可用——两头不讨好。**v2 全部修正**：

| 项 | v1 | **v2** |
|---|---|---|
| 令牌 | 放宽（加组+留特权） | **与 workspace-write 完全一致的严格令牌**（WRITE_RESTRICTED + 能力 SID + 无特权） |
| C:\ 根目录写入 | ✅ 可写（泄露） | ❌ **DENIED（实测）** |
| 用户目录/桌面写入 | ❌ | ❌ DENIED（实测） |
| C:\Users\Public 写入 | ✅ 可写 | ⚠️ 仍可写（Everyone 是受限令牌**必需保活组**，机制下限；Public 为系统共享区，非用户数据） |
| WMI/CIM | ✅（靠放宽令牌） | ❌ 与 workspace-write 一致（严格令牌的固有取舍，文档明示） |
| **HTTPS（curl.exe）** | ❌ | ✅ **可用**（PATH 注入 OpenSSL/LibreSSL 版 curl，实测 HTTP 200 verify=0） |

**HTTPS 的解法**：不碰 Schannel（受限令牌下无解，见 [调查记录](docs/findings-zh.md)），而是由 runner 在 net-access 模式下把非 Schannel 的 curl 目录**前置到 PATH** 并设置 `CURL_CA_BUNDLE` —— 沙箱里敲 `curl.exe` 直接走 LibreSSL 完成 TLS。

## 特性表

| 能力 | workspace-write | **net-access (v2)** | full access |
|---|---|---|---|
| 工作区写入 | ✅ | ✅ | ✅ |
| 工作区外写入（用户数据/C:\根） | ❌ | ❌ | ✅ |
| C:\Users\Public 写入 | ⚠️ | ⚠️（机制下限） | ✅ |
| WMI/CIM | ❌ | ❌ | ✅ |
| `curl.exe` HTTPS（OpenSSL 版） | ❌ | ✅ | ✅ |
| node / python HTTPS | ✅ | ✅ | ✅ |
| 系统 curl / Invoke-WebRequest（Schannel） | ❌ | ❌ | ✅ |

## 安装

### 1. 引擎补丁（必须）

```powershell
.\install.ps1
```

自动扫描所有 DSH 安装位置，逐文件：备份 `*.netaccess.bak` → 覆盖 → SHA256 校验。幂等可重跑。

### 2. 部署 HTTPS 工具箱（net-access 生效前提）

在你自己的控制台执行一次（把 OpenSSL/LibreSSL 版 curl 放到 runner 约定的目录）：

```powershell
# 1) 从 https://curl.se/windows/ 下载官方 win64 版 curl 并解压（任意目录）
# 2) 把 curl.exe 和 CA 证书复制到约定位置（<解压目录> 换成你的实际路径）：
New-Item -ItemType Directory -Force "$env:USERPROFILE\.dsh\netaccess-tools\bin" | Out-Null
Copy-Item "<解压目录>\bin\curl.exe", "<解压目录>\bin\curl-ca-bundle.crt" "$env:USERPROFILE\.dsh\netaccess-tools\bin\"
```

`%USERPROFILE%\.dsh\netaccess-tools\bin` 是**通用位置**（每台机器自动解析到各自用户目录），也可用环境变量 `DSH_NETACCESS_TOOLBIN` 指向其他目录。

### 3. 预设注册（二选一）

```powershell
dsh plugin add .\plugin            # 本地插件形态
# 或手动：把 patches\profile-cordis.patch.yml 覆盖到 %USERPROFILE%\.dsh\profiles\web\cordis.patch.yml（先备份）
```

### 4. 重启生效

```powershell
dsh restart
```

浏览器硬刷新（Ctrl+Shift+R）后，权限选择器出现 **Net Access**（盾牌+地球图标）。

## 验证

```powershell
curl.exe -sS -o NUL -w "%{http_code}" https://example.com   # 200（沙箱内 PATH 已注入）
python -c "import urllib.request; print(urllib.request.urlopen('https://example.com').status)"  # 200
Set-Content "$env:USERPROFILE\Desktop\test.txt" 'x'          # 拒绝访问
New-Item -ItemType Directory C:\na_test                      # 拒绝访问
```

## 威胁模型与边界（v2）

| 场景 | 状态 |
|---|---|
| 破坏用户数据（主目录/桌面） | ❌ 被 WRITE_RESTRICTED 拦截（实测） |
| 在 C:\ 根创建条目 | ❌ 拦截（实测） |
| 写 C:\Users\Public | ⚠️ 允许——Everyone 是受限令牌启动所必需的保活组（去掉进程无法启动，已实证）；Public 为系统共享区 |
| 读取系统元数据（WMI/进程枚举） | ❌ WMI 不可用（严格令牌丢 Authenticated Users，与 workspace-write 相同） |
| 数据外泄（网络外传） | ⚠️ 不设防——net-access 本就不限制网络；需防外泄请用断网环境或人工审批兜底 |
| 本地提权 | 低——非提权 + 无特权令牌（DISABLE_MAX_PRIVILEGE），实测无 SeImpersonate |
| 供应链（仓库被篡改） | SHA256 校验防意外损坏；建议核对 git commit |
| Schannel HTTPS | ❌ 任何受限令牌模式均不可用（平台死结，见 docs/findings-zh.md）；用 OpenSSL 版 curl/python/node |

## 卸载

```powershell
.\uninstall.ps1     # 恢复 *.netaccess.bak + 预设备份
dsh restart
```

## 目录结构

```
patches/                   # 9 个打过补丁的引擎/客户端文件 + 预设补丁
plugin/                    # 标准 dsh 插件形态（预设部分）
install.ps1 / uninstall.ps1 / manifest.json
docs/findings-zh.md        # 完整调查记录（WRITE_RESTRICTED vs SSPI 死结、v1→v2 演进）
assets/net-access-icon.svg
extras/dsh-launcher.ps1    # 可选后台启停启动器
```

## 通用性说明（换机器/别人能用吗）

**机制层：完全通用。** 补丁只使用标准 Windows 机制（CreateRestrictedToken/WRITE_RESTRICTED、能力 SID、PATH/CURL_CA_BUNDLE 注入），不依赖任何单机特殊配置；写边界行为（用户数据 DENIED、C:\根 DENIED、Public 可写）由 **Windows 默认 ACL** 决定，任何正常安装的 Windows 行为一致。安装脚本自动发现各机器的 DSH 安装位置（npm 缓存/`~/.dsh/profiles`/全局 npm），工具箱位置 `%USERPROFILE%\.dsh\netaccess-tools\bin` 逐机解析。

**版本层：绑定 dsh rc.6。** 补丁打在 rc.6 的构建产物（lib/ 编译文件）上，换 DSH 版本需重新对齐（SHA256 校验会立刻提示不匹配）。

**使用前提**：Windows + Node.js + DSH `0.1.0-rc.6` + 自备 OpenSSL/LibreSSL 版 curl（curl.se 下载）。

**分享给别人**：仓库当前为 private，需在 GitHub 仓库 Settings 里改为 public 后，别人才能 `git clone` 或 `dsh plugin add`；对方按"安装"三步执行即可。

## 上游化建议

- `packages/sandbox/windows-acl` runner：增加 net-access 模式的工具目录 PATH/CURL_CA_BUNDLE 注入；
- `packages/sandbox`/`sandbox-policy`/`permission-presets`：模式词汇表与预设加入 `net-access`；
- 真正"写保护 + Schannel HTTPS"两全需要绕开令牌：代理中介（broker，全令牌 sidecar 终止 TLS）或 AppContainer 沙箱。

## 许可

MIT。本补丁包与 DeepSeek AI 无关，非官方发布。
