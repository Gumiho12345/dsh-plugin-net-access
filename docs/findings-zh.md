# 调查记录：为什么 Windows 沙箱会卡死 HTTPS，net-access 是怎么来的

本文是 dsh-plugin-net-access 的完整背景调查记录（2026-08-15，Windows 11 26100/26200，dsh 0.1.0-rc.6）。

## 1. 症状

用户机器上 `Invoke-WebRequest` 与 `curl.exe` 的所有 HTTPS 请求失败，报：

```
schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS (0x8009030e)
```

但：DNS 解析 ✅、TCP 443 连通 ✅、明文 HTTP ✅、浏览器 ✅、Python/OpenSSL TLS ✅、桌面控制台 curl ✅。

## 2. 定位过程

| 检查 | 结果 | 结论 |
|---|---|---|
| 系统时钟 vs HTTP Date 头 | 一致 | 排除时间偏差 |
| 根证书库 / 密码套件 / SCHANNEL 注册表 | 正常 | 排除证书/配置问题 |
| Python(OpenSSL) TLS | ✅ | 网络层完全正常 |
| 桌面控制台 curl | ✅ | **机器本身完全正常** |
| GUI 命令通道内所有 SSPI 出站 | ❌ 0x8009030E；入站 ✅ | 问题在进程令牌 |

关键模式：**GUI 通道的每条命令都被 DSH 沙箱以"受限令牌"运行**（`CreateRestrictedToken` + Job Object），而桌面控制台是正常令牌。SSPI 出站（Schannel/NTLM/Negotiate）全部失败、入站正常、枚举正常、DPAPI 正常 —— 典型的"受限令牌过不了 LSA 出站访问检查"特征。

## 3. 沙箱令牌构造（dsh-sandbox-windows-acl）

- `CreateRestrictedToken(flags=13)`：13 = `DISABLE_MAX_PRIVILEGE(1) | SANDBOX_INERT(2) | LUA_TOKEN(4) | WRITE_RESTRICTED(8)`
- 限制 SID：`[Logon SID, Everyone, 工作区能力 SID, 临时目录能力 SID]`
- 同时移除 **Authenticated Users / INTERACTIVE / LOCAL** 组（为关闭 WMI 与 Public 树写入）
- 文件写保护机制：WRITE_RESTRICTED 的"pass-2"检查 —— 写操作必须有一个限制 SID 在白名单上，而只有工作区/临时目录的 DACL 给能力 SID 授了写权限

## 4. 标志位矩阵实验（6 组变体，均在真实 runner 中验证）

| flags | 含义 | 进程启动 | SSPI 出站 |
|---|---|---|---|
| 13 | 全标志（=workspace-write） | ✅ | ❌ 0x8009030E |
| 12 | 保留特权（去 DISABLE_MAX_PRIVILEGE） | ✅ | ❌ |
| 9 | 去 LUA_TOKEN | ✅ | ❌ |
| 5 | 去 WRITE_RESTRICTED | ❌ STATUS_DLL_NOT_FOUND (0xC0000135) | — |
| 1 | 仅 DISABLE_MAX_PRIVILEGE | ❌ 同上 | — |
| 0 | 无标志 | ❌ 同上 | — |

加回组（Authenticated Users/INTERACTIVE/LOCAL）对 SSPI 无效；特权也无效。

## 5. 结论（平台机制级）

- **WRITE_RESTRICTED 是进程能启动的前提**（CNG/加载器依赖，去掉后 DLL 加载失败）；
- **WRITE_RESTRICTED 同时是 SSPI 出站失败的根源**（LSA 的出站凭证检查过不了 pass-2）；
- 二者在同一令牌内互斥 → **任何基于 `CreateRestrictedToken` 的 Windows 沙箱都无法让 Schannel 工作**。这不是配置错误，是平台约束。
- Linux（bwrap/Landlock）与 macOS（Seatbelt）的沙箱不限制网络，无此问题 —— 这是 Windows 特有问题。

## 6. net-access 设计

在保持 WRITE_RESTRICTED（写保护不变）的前提下：
1. 限制 SID 加入 **Authenticated Users / INTERACTIVE / LOCAL**（恢复 WMI/CIM、读取、正常用户组）；
2. 保留默认特权（flags=12）；
3. 结果：写保护 ✅、WMI ✅、读取 ✅、Python/OpenSSL HTTPS ✅；Schannel ❌（硬限制，如实文档化）。

## 7. WMI/CIM 风险分析

- WMI 按调用者令牌做 ACL 判断，**不是提权通道**：net-access 下能读到的就是该账户正常能看到的系统元数据（进程/服务/硬件/账户名/网络配置）；
- 操作类调用（如 `Win32_Process.Create`）受受限令牌约束，子进程继承受限令牌，仍写不了工作区外；
- 持久化玩法（WMI 事件订阅）需管理员权限，非提权进程不可用；
- 净增风险：相比 workspace-write 多暴露"系统元数据可枚举"，对自用单机 + `ask` 审批场景可忽略；不信任脚本时切回 workspace-write 即可。

## 8. 真正的两全方案（给上游）

1. **代理中介（broker）**：沙箱进程走明文 TCP 到全令牌 sidecar，由 sidecar 终止 TLS（注意：CONNECT 隧道不够，客户端仍需自己做 TLS 握手 → 必须 MITM 终止或使用非 Schannel 客户端）；
2. **AppContainer 沙箱**：UWP 式容器天然支持 Schannel，但 CLI 兼容性与配置复杂度高；
3. 或接受现状：写保护 + 非 Schannel TLS（本补丁包的方案）。
