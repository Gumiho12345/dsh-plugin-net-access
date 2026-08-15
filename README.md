# dsh-plugin-net-access

给 DSH 加一个 `net-access` 权限模式（仅 Windows）：**文件写保护和 workspace-write 一样严格，但沙箱里的 curl.exe 能用 HTTPS**。

## 原理

DSH 的 Windows 沙箱靠受限令牌（WRITE_RESTRICTED）挡写，副作用是沙箱里所有走 Schannel 的 HTTPS 都会挂（0x8009030E）。这是 Windows 平台的硬限制，改令牌救不回来（试过 6 种组合，记录在 docs/findings-zh.md）。

所以 net-access 的令牌和 workspace-write **完全一样**，runner 只额外做了一件事：把非 Schannel 版 curl 的目录前置到 PATH，并设置 `CURL_CA_BUNDLE`。沙箱里敲 `curl.exe` 走的是 LibreSSL，HTTPS 就能用了。

## 安装

1. 跑 `install.ps1` —— 自动找 DSH 安装位置，逐文件备份 + 覆盖 + SHA256 校验，可重复运行
2. 从 [curl.se](https://curl.se/windows/) 下载官方 win64 版 curl，把 `curl.exe` 和 `curl-ca-bundle.crt` 放进 `%USERPROFILE%\.dsh\netaccess-tools\bin\`（不想用默认位置就设环境变量 `DSH_NETACCESS_TOOLBIN`）
3. 预设二选一：`dsh plugin add .\plugin`，或把 `patches\profile-cordis.patch.yml` 复制到 `~\.dsh\profiles\web\cordis.patch.yml`（先备份原文件）
4. `dsh restart`，硬刷新浏览器，权限选择器选 **Net Access**

## 验证

```powershell
curl.exe -sS https://example.com                       # 200
Set-Content "$env:USERPROFILE\Desktop\t.txt" x         # 拒绝访问
New-Item -ItemType Directory C:\t                      # 拒绝访问
```

## 边界

- 用户数据、C:\ 根目录：写保护生效；`C:\Users\Public` 挡不住——Everyone 是受限令牌必需的保活组，机制下限
- WMI 和 workspace-write 一样不可用
- 系统 curl / Invoke-WebRequest（Schannel）依然不行：用 OpenSSL 版 curl / python / node，或切 full access
- 绑定 DSH 0.1.0-rc.6，升级 DSH 后需重新打补丁（install.ps1 校验会提示）

## 卸载

`uninstall.ps1` 恢复备份，`dsh restart`。

## 上游

这套改动（runner 注入 + 模式词汇表）应该进官方仓库，见 docs/findings-zh.md。
