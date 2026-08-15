# dsh-plugin-net-access

DeepSeek Harness (DSH) **Net Access** 权限模式补丁包：工作区文件写保护不变，同时恢复被沙箱令牌手术误伤的 Windows API（WMI/CIM、读取、正常用户组）。

> 状态：为 `@deepseek-ai/dsh 0.1.0-rc.6`（Windows）制作。核心引擎改动以补丁包形式提供（rc.6 的模式词汇表是编译期闭合的，无法用纯配置插件实现）；预设部分同时提供了标准 dsh 插件形态（`plugin/`）。

## 为什么需要它

DSH 的 Windows 沙箱用 `CreateRestrictedToken`（WRITE_RESTRICTED + 限制 SID + 移除 Authenticated Users/INTERACTIVE/LOCAL）实现文件写保护。该令牌会**连带卡死所有 SSPI 出站调用**（Schannel HTTPS、NTLM、WMI），表现就是 GUI 命令通道里 `curl`/`Invoke-WebRequest` 全部 `SEC_E_NO_CREDENTIALS (0x8009030E)`。

经过 6 组令牌标志位矩阵实测，这是平台机制级死结：

| 变体 | 结果 |
|---|---|
| 加回 Authenticated Users / INTERACTIVE / LOCAL 组 | ❌ SSPI 仍失败 |
| 保留默认特权 | ❌ 仍失败 |
| 去掉 WRITE_RESTRICTED | ❌ 进程无法启动（STATUS_DLL_NOT_FOUND） |

**net-access 的定位**：保持 WRITE_RESTRICTED 写保护（工作区+临时目录可写，其余拒绝），把组/特权恢复到正常用户水平 → WMI/CIM、读取恢复，非 Schannel TLS 客户端（Python/OpenSSL）可用。**Schannel HTTPS（curl/IWR）在任何受限令牌模式下都不可能工作**——需要 HTTPS 请用 Python/OpenSSL，或临时切 Full access（完整令牌）。

## 特性

| 能力 | workspace-write | **net-access** | full access |
|---|---|---|---|
| 工作区写入 | ✅ | ✅ | ✅ |
| 工作区外写入 | ❌ | ❌ | ✅ |
| WMI/CIM (`Get-CimInstance`) | ❌ 拒绝访问 | ✅ 恢复 | ✅ |
| 工作区外读取 | ❌ | ✅ 恢复 | ✅ |
| Python/OpenSSL HTTPS | ✅ | ✅ | ✅ |
| curl/IWR HTTPS (Schannel) | ❌ | ❌ | ✅ |

## 安装

### 1. 引擎补丁（必须）

以管理员/普通权限打开 PowerShell，在仓库目录运行：

```powershell
.\install.ps1
```

脚本会扫描所有 DSH 安装位置（npx 缓存、`~\.dsh\profiles`、npm 全局），对每个目标文件：备份为 `*.netaccess.bak` → 覆盖为补丁版本 → SHA256 校验。可重复运行（已备份则跳过）。

### 2. 预设注册（二选一）

**方式 A — dsh 插件（推荐）**：

```powershell
# 本地目录方式
dsh plugin add .\plugin        # 在仓库根目录运行
# 或发布到 GitHub 后：
dsh plugin add dsh-plugin-net-access   # 按 dsh plugin 的实际用法
```

**方式 B — 手动**：把 `patches\profile-cordis.patch.yml` 复制为 `%USERPROFILE%\.dsh\profiles\web\cordis.patch.yml`（先备份原文件）。

### 3. 重启生效

```powershell
dsh restart   # 或：杀掉 3080 端口进程后重新 npx @deepseek-ai/dsh web
```

浏览器打开 `http://127.0.0.1:3080` 并**硬刷新**（Ctrl+Shift+R）。左下角权限选择器出现 **Net Access**（盾牌+地球图标）。

## 验证

```powershell
Get-CimInstance Win32_OperatingSystem        # 应正常返回（net-access 前是拒绝访问）
python -c "import urllib.request; print(urllib.request.urlopen('https://example.com',timeout=15).status)"   # 200
# 工作区外写入应被拒：
Set-Content "$env:USERPROFILE\Desktop\test.txt" 'x'   # 应报拒绝访问
```

## 卸载

```powershell
.\uninstall.ps1     # 从 *.netaccess.bak 恢复所有文件
# 删除预设：还原 profile 的 cordis.patch.yml 备份 / dsh plugin remove
dsh restart
```

## 目录结构

```
patches/                  # 9 个打过补丁的引擎/客户端文件（按包相对路径存放）
  profile-cordis.patch.yml # 权限预设补丁（用户层）
plugin/                   # 标准 dsh 插件形态（仅预设部分）
install.ps1 / uninstall.ps1 / manifest.json
docs/findings-zh.md       # 完整调查记录（标志位矩阵、WMI 风险分析）
assets/net-access-icon.svg
extras/dsh-launcher.ps1   # 可选：后台启停启动器（dsh start/stop/restart/status）
```

## 上游化建议（给官方仓库）

- `packages/sandbox/windows-acl`：`createRestrictedToken` 增加 `net-access` 分支（限制 SID 加入 AU/INTERACTIVE/LOCAL，flags 12）；
- `packages/sandbox` / `packages/sandbox-policy` / `packages/permission-presets`：模式词汇表与预设表加入 `net-access`；
- 客户端：权限选择器 glyph 增加 net-access 条目；
- README 记录 `WRITE_RESTRICTED` 与 LSA 出站 SSPI 的兼容性结论；
- 真正的"写保护 + Schannel HTTPS"两全方案需要绕开令牌机制：代理中介（broker，由全令牌 sidecar 终止 TLS）或 AppContainer 沙箱。

## 许可

MIT。本补丁包与 DeepSeek AI 无关，非官方发布。
