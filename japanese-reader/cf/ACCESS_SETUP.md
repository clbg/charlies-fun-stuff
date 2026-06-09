# Cloudflare Access 鉴权配置（手动，UI 操作）

> ✅ 已完成配置（2026-06-08）：应用 `jr-app`，策略 `Only me`（仅 charlie.pengcheng@hotmail.com），
> 登录方式 One-time PIN。已验证未登录访问被 302 拦截到 chengpeng.cloudflareaccess.com。

> 部署 token 没有 Access scope，这步无法用 CLI 自动化，需在 Cloudflare 后台点几下。
> 目标：只有你本人（指定邮箱）能访问 `https://jr-app.chengpeng.press`，其他人连页面都加载不到。

## 前提（已完成）
- ✅ Worker 已部署，绑定自定义域名 `jr-app.chengpeng.press`
- ✅ 域名 `chengpeng.press` 在你的 Cloudflare 账号，zone active

## 步骤

### 1. 进 Zero Trust 控制台
打开 https://one.dash.cloudflare.com/ → 选你的账号。
首次会让你起一个 **team 名**（生成 `<team>.cloudflareaccess.com` 登录域），随便起，选 **Free** 计划（$0，50 用户，不要信用卡）。

### 2. 添加身份提供商（Google）
左侧 **Settings → Authentication → Login methods → Add new**：
- 选 **Google**（用你已有的 Google 账号），按引导授权；
- 或更省事：直接用预置的 **One-time PIN**（输邮箱收验证码，无需配 Google）。

### 3. 新建 Access 应用
左侧 **Access → Applications → Add an application → Self-hosted**：
- **Application name**: `Japanese Reader`
- **Session duration**: 选 `1 week`（自用，不用频繁登录）
- **Public hostname**:
  - Subdomain: `jr-app`
  - Domain: `chengpeng.press`
  - （即完整 `jr-app.chengpeng.press`）
- **Identity providers**: 勾选你第 2 步加的（Google / One-time PIN）
- （可选）打开 **Instant Auth**，跳过 Access 自带的选择页，直接跳 Google 登录

### 4. 加策略（只允许你本人）
进入应用的 **Policies → Add a policy**：
- **Policy name**: `Only me`
- **Action**: `Allow`
- **Configure rules → Include**:
  - Selector: `Emails`
  - Value: 填你的邮箱（实配 `charlie.pengcheng@hotmail.com`）
- Save。

### 5. 完成 + 验证
保存应用。然后访问 https://jr-app.chengpeng.press ：
- 会先跳转到 Cloudflare Access 登录页 → 用你的邮箱登录 → 通过后才进入 app；
- 用别的邮箱登录 → 看到 "That account does not have access"。

## 注意
- `/api/*` 和前端 SPA 都在同一个 hostname 下，**一条策略全罩住**，无需额外配置。
- 改邮箱/加设备：回到 Policies 编辑即可，实时生效。
- 这套是边缘鉴权，app 代码里没有任何鉴权逻辑——撤销访问只需删策略。
