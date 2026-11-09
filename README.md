# TokenMinister

TokenMinister 是一个 Windows 桌面小组件，用来安静地查看 OpenCode Go 套餐的真实 dashboard 额度。它显示 5 小时、每周、每月三档的剩余百分比、重置倒计时和最近更新时间。

它不会把百分比伪装成无法验证的 Token 数，也不读取 CC Switch 数据库。只要 CC Switch 中使用的是同一个 OpenCode Go 账号，无论额度由 Claude、Codex 或其他客户端消耗，最终都以该账号的 OpenCode dashboard 为准。

## 工作方式

- OpenCode 于 2026-09-22 下线了 onWatch 抓取的 dashboard 页面（上游 [issue #134](https://github.com/onllm-dev/onwatch/issues/134)）。浮窗现在直接轮询 OpenCode 控制台的 `GET https://opencode.ai/console/api/go/status`（带 `x-org-id: <workspace ID>` 头），把返回的微分数换算为剩余百分比，每 30 秒刷新一次。
- [onWatch v2.14.3](https://github.com/onllm-dev/onwatch/releases/tag/v2.14.3) 随组件启动，继续在本机记录 Kimi Code、Codex 等其他 provider 的用量（其 dashboard 见 `http://127.0.0.1:9211`），但浮窗不再读取它的 OpenCode 数据。
- 网络、登录或解析失败时，浮窗保留最后一次成功值并显示“数据过期”，不会回退到本地估算，也不会把额度重置成零。
- OpenCode 没有返回月额度重置时间时，以 access.endsAt 兜底。

## 系统要求

- Windows 10/11 AMD64（x64）
- Windows PowerShell 5.1
- 一个有效的 OpenCode Go workspace

安装器会拒绝非 AMD64 系统。它固定下载 onWatch `v2.14.3` Windows AMD64，并校验：

```text
SHA-256 A8DA1F0D89689C0F5B2735C1EF7298AA9493A600222146EEF42FF527985EC9E1
```

安装器不会添加 Windows Defender 排除项。若安全软件拦截二进制，应先核对上述哈希和上游发布页，再自行决定是否允许；不要关闭系统防护。

## 安装

在项目目录打开 PowerShell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -StartNow
```

安装内容位于 `%LOCALAPPDATA%\TokenMinister`，并在桌面和当前用户启动目录分别创建 `TokenMinister.lnk`。两者都使用 TokenMinister 专用图标；双击桌面快捷方式即可启动，登录 Windows 时也会自动启动。首次启动会要求两个值：

1. 登录 [opencode.ai](https://opencode.ai) 控制台，打开 Go 用量页面后从地址栏或控制台复制 `wrk_...` workspace ID。
2. 在浏览器开发者工具的 Application/Storage → Cookies → `https://opencode.ai` 中，找到 **`__Host-console_session`**（改版后 `auth` cookie 已废弃，不再认证任何接口），右键该行选择 Copy → Value 复制其值，不要包含 `__Host-console_session=` 前缀。手动划选可能复制到遮罩星号，务必使用右键复制。

Cookie 等同于账号密码。不要把它粘贴到日志、Issue 或聊天中。

## 使用

浮窗始终置顶、不会出现在任务栏，可以直接拖动。托盘菜单包含：

- 显示/隐藏
- 立即重读
- 更新凭据
- 重启后端
- 退出

窗口位置会跨重启保存；显示器布局变化后，窗口会自动移回当前可见区域。组件不发送系统通知，也不根据额度阈值改变颜色。

onWatch 继续按自己的轮询周期记录其他 provider；浮窗中的 OpenCode 三档数据在消耗后最多 30 秒内更新。

## 凭据与本地数据

- Workspace ID：明文保存在 `%LOCALAPPDATA%\TokenMinister\settings.json`。
- `__Host-console_session` cookie：使用 Windows DPAPI `CurrentUser` 作用域加密，保存在 `%LOCALAPPDATA%\TokenMinister\credentials.dat`。
- Cookie 解密后仅用于浮窗对 `https://opencode.ai/console/api/go/status` 的直连请求，不写入任何文件或环境变量。
- onWatch 历史：默认位于 `%USERPROFILE%\.onwatch\data\onwatch.db`。
- 服务只绑定 `127.0.0.1:9211`。

如果数据持续无法刷新，浮窗会显示“数据过期”，把鼠标悬停在状态区可以看到具体错误。通过托盘的“更新凭据”保存新 cookie 后，组件会立即重读，无需重启后端。

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

- 浮窗依赖未公开的 `console/api/go/status` 接口，OpenCode 控制台再次改版可能导致抓取暂时失效（上游修复进展见 [onWatch issue #134](https://github.com/onllm-dev/onwatch/issues/134)）。
- `__Host-console_session` cookie 在退出登录、清除浏览器数据或服务端轮换会话后会失效。
- v1 只支持一个 workspace，不支持告警、CC Switch 自动跟随或精确 Token 数。
- 本项目只报告抓取失效，不估算或伪造额度。

第三方归属和许可证信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
