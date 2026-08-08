# TokenMinister

TokenMinister 是一个 Windows 桌面小组件，用来安静地查看 OpenCode Go 套餐的真实 dashboard 额度。它显示 5 小时、每周、每月三档的剩余百分比、重置倒计时和最近更新时间。

它不会把百分比伪装成无法验证的 Token 数，也不读取 CC Switch 数据库。只要 CC Switch 中使用的是同一个 OpenCode Go 账号，无论额度由 Claude、Codex 或其他客户端消耗，最终都以该账号的 OpenCode dashboard 为准。

## 工作方式

- [onWatch v2.13.3](https://github.com/onllm-dev/onwatch/releases/tag/v2.13.3) 每 120 秒抓取已登录的 OpenCode Go dashboard，并把快照保存在本机 SQLite。
- PowerShell/WPF 浮窗每 30 秒读取 `http://127.0.0.1:9211/api/menubar/summary`，把 onWatch 返回的“已用百分比”换算为“剩余百分比”。
- 网络、登录或解析失败时，浮窗保留最后一次成功值并显示“数据过期”，不会回退到本地估算，也不会把额度重置成零。
- OpenCode 没有返回月额度时，月档明确显示“未提供”。

## 系统要求

- Windows 10/11 AMD64（x64）
- Windows PowerShell 5.1
- 一个有效的 OpenCode Go workspace

安装器会拒绝非 AMD64 系统。它固定下载 onWatch `v2.13.3` Windows AMD64，并校验：

```text
SHA-256 EC5764CC98ED05CA887C9D541A521163F936C017B771A28BE7CAA710FD03EEC9
```

安装器不会添加 Windows Defender 排除项。若安全软件拦截二进制，应先核对上述哈希和上游发布页，再自行决定是否允许；不要关闭系统防护。

## 安装

在项目目录打开 PowerShell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -StartNow
```

安装内容位于 `%LOCALAPPDATA%\TokenMinister`，并在桌面和当前用户启动目录分别创建 `TokenMinister.lnk`。两者都使用 TokenMinister 专用图标；双击桌面快捷方式即可启动，登录 Windows 时也会自动启动。首次启动会要求两个值：

1. 登录 [opencode.ai](https://opencode.ai)，打开形如 `https://opencode.ai/workspace/wrk_xxxxx/go` 的页面，复制 URL 中的 `wrk_...` workspace ID。
2. 在浏览器开发者工具的 Application/Storage → Cookies → `https://opencode.ai` 中，复制 `auth` cookie 的值，不要包含 `auth=` 前缀。

Cookie 等同于账号密码。不要把它粘贴到日志、Issue 或聊天中。

## 使用

浮窗始终置顶、不会出现在任务栏，可以直接拖动。托盘菜单包含：

- 显示/隐藏
- 立即重读
- 更新凭据
- 重启后端
- 退出

窗口位置会跨重启保存；显示器布局变化后，窗口会自动移回当前可见区域。组件不发送系统通知，也不根据额度阈值改变颜色。

onWatch 首次成功抓取可能需要一个轮询周期。通过 CC Switch 消耗额度后，通常应在最多两个 120 秒后端轮询周期内反映出来。

## 凭据与本地数据

- Workspace ID：明文保存在 `%LOCALAPPDATA%\TokenMinister\settings.json`。
- `auth` cookie：使用 Windows DPAPI `CurrentUser` 作用域加密，保存在 `%LOCALAPPDATA%\TokenMinister\credentials.dat`。
- Cookie 解密后只在启动 onWatch 子进程时临时写入进程环境；子进程创建后，组件会立即恢复原环境变量。组件不会为 onWatch 写入包含 cookie 的 `.env`。
- onWatch 历史：默认位于 `%USERPROFILE%\.onwatch\data\onwatch.db`。
- 服务只绑定 `127.0.0.1:9211`。

如果数据超过 10 分钟未更新，浮窗会提示检查登录凭据。通过托盘的“更新凭据”保存新 cookie 后，组件会重启后端并自动重读。

## 卸载

先从托盘退出浮窗，再运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

卸载会停止随组件启动的 onWatch，删除启动项、组件文件和 DPAPI 凭据。默认保留 `%USERPROFILE%\.onwatch` 下的 onWatch 历史数据；如需彻底清除，请在确认路径与内容后自行删除该目录。

## 开发与验证

运行全部测试：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

测试包含额度解析边界、缺少月档、缺少 provider、无效 JSON、过期判断、DPAPI、回环 HTTP、断线保留、后端环境隔离与重启、固定哈希、单实例、启动项安装/卸载，以及 WPF XAML 加载。

仅校验界面资源而不弹出窗口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\TokenMinister.ps1 -ValidateOnly
```

## 已知限制

- OpenCode 尚未提供公开额度 API；onWatch 依赖未公开的 dashboard HTML，页面变化可能导致抓取暂时失效。
- Cookie 在退出登录、清除浏览器数据或服务端轮换会话后会失效。
- v1 只支持一个 workspace，不支持告警、CC Switch 自动跟随或精确 Token 数。
- 本项目只报告抓取失效，不估算或伪造额度。

第三方归属和许可证信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
