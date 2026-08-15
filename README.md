# dsh-plugin-net-access

DSH 的 `net-access` 权限模式补丁（仅 Windows）。

## 它能干什么

- **文件写保护照旧**：沙箱里和 workspace-write 一样，写不了工作区外的文件（用户数据、C:\ 根目录都会被拒）
- **沙箱里的 curl.exe 能用 HTTPS**：DSH 自带沙箱的受限令牌会让所有走 Schannel 的 HTTPS 报 `0x8009030E`（Windows 平台限制，原因见 docs/findings-zh.md），net-access 通过注入 OpenSSL 版 curl 绕开它
- 附带一个 **Net Access 权限预设**，左下角权限选择器里可选

## 已知限制

- `C:\Users\Public` 挡不住：Everyone 是受限令牌必需的保活组，机制下限
- 系统 curl / Invoke-WebRequest（走 Schannel）依然不能用：请用 OpenSSL 版 curl / python / node，或切 full access
- WMI 不可用（和 workspace-write 一样）
- 只支持 DSH `0.1.0-rc.6`，其他版本需重新打补丁

## 安装

前置：Windows + Node.js + DSH 0.1.0-rc.6

**1. 引擎补丁**

```powershell
.\install.ps1
```

脚本自动找 DSH 安装位置，逐文件备份（`*.netaccess.bak`）后覆盖，带 SHA256 校验，可重复运行。

**2. HTTPS 工具箱**（net-access 下 curl 能用 HTTPS 的前提）

从 [curl.se](https://curl.se/windows/) 下载官方 win64 版 curl，解压后把 `curl.exe` 和 `curl-ca-bundle.crt` 复制到：

```
%USERPROFILE%\.dsh\netaccess-tools\bin\
```

（不想用这个位置，就设环境变量 `DSH_NETACCESS_TOOLBIN` 指到别的目录。）

**3. 权限预设**（二选一）

```powershell
dsh plugin add .\plugin
```

或手动：把 `patches\profile-cordis.patch.yml` 复制到 `%USERPROFILE%\.dsh\profiles\web\cordis.patch.yml`（先备份原文件）。

## 使用

1. **重启 DSH**（官方方式）：在启动 DSH 的终端按 `Ctrl+C`，或 `netstat -ano | findstr 3080` 查到进程号后 `taskkill /F /PID <进程号>`，再重新运行 `npx @deepseek-ai/dsh web`
2. 打开 `http://127.0.0.1:3080`，硬刷新浏览器，左下角权限选择器选 **Net Access**

## 验证

```powershell
curl.exe -sS https://example.com                    # 200
Set-Content "$env:USERPROFILE\Desktop\t.txt" x      # 拒绝访问
New-Item -ItemType Directory C:\t                   # 拒绝访问
```

## 卸载

```powershell
.\uninstall.ps1
```

（恢复所有备份文件），还原 `cordis.patch.yml`，重启 DSH。

## 上游

这套改动（runner 注入 + 模式词汇表）应该进官方仓库，详见 docs/findings-zh.md。
