# Packaging & Distribution — Undercurrent

## 方式一：发 .dmg（推荐，最傻瓜）

朋友收到 `.dmg`，双击 → 拖入 Applications → 打开。

```bash
# 你构建
pnpm dist

# 产物在 dist/ 下
# dist/Undercurrent-0.1.0-arm64.dmg   ← Apple Silicon Mac
# dist/Undercurrent-0.1.0.dmg          ← Intel Mac
```

朋友唯一需要做的：
1. 装 Node.js（`brew install node` 或从 nodejs.org 下载）
2. 装 Claude CLI：`npm install -g @anthropic-ai/claude-code`
3. 终端运行一次 `claude` 完成登录
4. 双击 Undercurrent.app

> App 启动时如果没检测到 `claude`，会弹窗提示安装步骤。

## 方式二：发源码 + `./start.sh`

```bash
# 你打包
tar czf undercurrent.tar.gz \
  --exclude=node_modules \
  --exclude=.next \
  --exclude=.git \
  --exclude=dist \
  --exclude=electron-resources \
  .
```

朋友：
```bash
tar xzf undercurrent.tar.gz && cd undercurrent && ./start.sh
```

`start.sh` 自动检查/安装 Node、pnpm、Claude CLI，然后启动并打开浏览器。

## 构建原理

`pnpm dist` 做了三件事：

1. `next build`（output: standalone）→ 最小化的自包含 Node.js 服务器
2. 把 standalone + static + public 拷贝到 `electron-resources/`
3. `electron-builder` 打包成 `.app` → `.dmg`

App 启动时：找到系统 `node` → 运行内嵌的 `server.js` → 打开窗口指向 `localhost:3456`。

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Undercurrent" can't be opened (macOS Gatekeeper) | 右键 → Open，或 System Settings → Privacy → Allow |
| Claude CLI not found | App 会弹窗提示。装好后重新打开 |
| Auth expired | 终端运行 `claude` 重新登录 |
| App 启动后白屏 | 等几秒（standalone server 启动需要时间） |
