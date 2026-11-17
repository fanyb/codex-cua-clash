# Codex 内置浏览器 Clash 代理配置

Codex 内置浏览器初始化时，本机 `cua_repl` 会访问 ChatGPT 的身份和功能配置服务。如果这些请求直连超时，可以让浏览器控制进程通过 Clash 的本地 HTTP 代理发起 HTTPS 请求。配置一次后，照常从 Dock 或 Windows 开始菜单打开 Codex。Clash 的 TUN 可以关闭。

先从 [GitHub 下载 ZIP](https://github.com/fanyb/codex-cua-clash/archive/refs/heads/main.zip)，解压并在终端进入解压目录。运行前可直接阅读脚本。两套安装器均使用当前用户权限。

## macOS

保持 Clash 运行，在终端执行下面的命令。默认使用 HTTP 或混合端口 `7890`。端口不同时，在 `install` 后传入实际端口，例如 `install 7897`。

```bash
/bin/bash setup-macos.sh install
```

按 **⌘Q** 完全退出 Codex，再从 Dock 打开。用户登录项负责在每次登录后准备运行路径。

卸载时执行 `/bin/bash setup-macos.sh uninstall`，然后重开 Codex。

## Windows（预览）

先用原生 Windows 后端打开一次 Codex 桌面版，并启用内置浏览器。安装器需要读取应用已经生成的本地浏览器插件配置，以确认 Node 和 `node_repl.exe` 的位置。保持 Clash 运行，在 PowerShell 中执行下面的命令。端口不同时追加 `-Port 7897`，把 `7897` 换成实际 HTTP 或混合端口。

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\setup-windows.ps1
```

如果 Windows 标记下载的脚本为来自 Internet，检查脚本后执行 `Unblock-File -LiteralPath .\setup-windows.ps1`，再重跑安装命令。`RemoteSigned` 只用于这次 PowerShell 进程。

从托盘彻底退出 Codex，再从开始菜单重开。若新进程仍使用旧的环境设置，注销 Windows 后重新登录再试。Windows 路径使用用户环境变量保存运行路径，并在本机用 Windows PowerShell 5.1 编译仓库中的 C# 启动程序。Windows 的 WSL 后端不在适用范围内。[Windows PowerShell Add-Type](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/add-type?view=powershell-5.1) · [Windows 用户环境变量](https://learn.microsoft.com/en-us/dotnet/api/System.Environment.SetEnvironmentVariable)

卸载前先彻底退出 Codex，再执行下面的命令。

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\setup-windows.ps1 -Action uninstall
```

## 验证

在 Codex 里发一句「用内置浏览器打开 `about:blank`，告诉我耗时并关闭测试页」。在测试时还可以核对 `node_repl` 到本地 Clash 的连接。若安装时使用其他端口，将下面命令里的 `7890` 同步替换。

```bash
/usr/sbin/lsof -nP -a -c node_repl -iTCP:7890
```

```powershell
Get-NetTCPConnection -RemoteAddress 127.0.0.1 -RemotePort 7890 -State Established |
    Where-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName -eq 'node_repl' }
```

- **macOS** 已在桌面版 `26.1111.21308` 上实测。TUN 关闭时，从 Dock 重开后首次打开空白页约 1.5 秒，并观察到 `node_repl` 连接 Clash。
- **Windows** 的 CI 测试覆盖安装、卸载、用户变量、启动参数、双向标准输入输出和按浏览器能力设置代理。开始菜单重启后使用真实 Codex 浏览器的端到端结果待验证。[检查记录](https://github.com/fanyb/codex-cua-clash/actions)

## 配置范围

两套脚本均通过 Codex 桌面版的 `CODEX_NODE_REPL_PATH` 接入。只有启用了浏览器能力的 `cua_repl` 会收到代理设置。浏览器页面的流量仍由浏览器及系统代理设置决定。保持 Clash 运行，应用升级后重做一次验证。已有自定义 `CODEX_NODE_REPL_PATH` 会触发安装检查，请先核对现有配置。
