# Cloudflare Access 鉴权配置（手动，UI 操作）

> ✅ **当前配置（2026-06-10）**：应用 `jr-app`，策略 `Only me`（仅 charlie.pengcheng@hotmail.com），
> 登录方式 = **Cloudflare 账号 IdP**（限制为帐户成员）+ **Instant Auth 直达**，可用 passkey / Touch ID。
> 已验证：登出后访问 → 跳 Cloudflare 登录 → CF 账号认证 → 回到 app，无邮箱验证码。

> 部署 token 没有 Access scope，这步无法用 CLI 自动化，需在 Cloudflare 后台点几下。
> 目标：只有你本人能访问 `https://jr-app.chengpeng.press`，其他人连页面都加载不到。

## 前提（已完成）
- ✅ Worker 已部署，绑定自定义域名 `jr-app.chengpeng.press`
- ✅ 域名 `chengpeng.press` 在你的 Cloudflare 账号，zone active
- ✅ Zero Trust 账号已开（team 名 `chengpeng`，Free 计划）

## 当前做法：用 Cloudflare 账号登录（推荐，可 passkey）

### 1. 加 Cloudflare 作为身份提供商
**Zero Trust → Integrations → Identity providers → 添加 → Cloudflare**：
- 打开「限制为帐户成员」（只有你 CF 账号成员能认证）→ 保存。

### 2. 应用改用 Cloudflare 登录
**Access → Applications → jr-app → 编辑 → 身份验证**：
- 关掉「接受所有可用的标识提供程序」
- 「选择此应用程序可用的身份提供程序」只选 **Cloudflare**
- 打开「应用即时身份验证（Instant Auth）」→ 单一 IdP 时可直达，跳过选择页
- 保存。

### 3. 策略（只允许你本人）
应用的 **Policies**：`Only me`，Action=`Allow`，Include → Emails = `charlie.pengcheng@hotmail.com`。

### 4. 设 passkey（在 Cloudflare 账号侧，不在 Access）
passkey 的"一碰就进"来自**你 Cloudflare 账号本身**：
- [dash.cloudflare.com/profile/authentication](https://dash.cloudflare.com/profile/authentication) → 加 passkey / security key。
- 之后 app 登录走 Cloudflare 账号时即可用 Touch ID / Face ID。

### 5. 验证
登出（访问 `https://chengpeng.cloudflareaccess.com/cdn-cgi/access/logout`）→ 打开 app → 应跳 Cloudflare 登录 → passkey 认证 → 进入 app。

## 备用：One-time PIN（早期方案，IdP 已保留未删）
上线初期用的是 One-time PIN（输邮箱收验证码，零配置）。该 IdP 仍在列表里，若 Cloudflare 登录出问题，可在「应用 → 身份验证」里切回它一键恢复。

## 注意
- `/api/*` 和前端 SPA 都在同一 hostname 下，**一条策略全罩住**，无需额外配置。
- 改邮箱/加设备/换登录方式：回到对应 IdP 或 Policy 编辑即可，实时生效。
- 边缘鉴权，app 代码里没有任何鉴权逻辑——撤销访问只需删策略。
- 只要你能登 Cloudflare 后台，就不会被永久锁死。
