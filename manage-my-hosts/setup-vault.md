# 在 Linux server 上自托管 Obsidian MCP 的执行任务书

你现在扮演一个可以通过 SSH 连接远程 Linux server 并完成部署的工程代理。  
目标是在**不暴露公网 HTTP endpoint**、**不依赖 Obsidian Desktop 常驻**、**尽量少改动现有环境**的前提下，为一个已经通过 Google Drive 同步到 Linux 本地目录的 Obsidian vault 搭建一个**可维护、可复现、便于后续本地 MCP 客户端通过 SSH 使用**的 MCP server。

---

## 1. 已知前提

- 用户的 Obsidian vault 存在于 Google Drive 中。
- Linux server 上已经有一个 Google Drive client 正在把 vault 同步到本地目录。
- 目标不是直接用 Google Drive API 做 MCP，而是直接对 Linux server 上**同步后的本地 vault 目录**提供 MCP 能力。
- 目标方案优先选用 **MCPVault** 这类直接操作 vault 目录的 MCP server。
- 本次部署默认走 **SSH + stdio** 模式，不额外搭建 HTTP / SSE / reverse proxy。
- 你需要尽量做到：
  - 可维护
  - 可阅读
  - 版本固定
  - 可重复执行
  - 风险保守
  - 尽量不要对 vault 内容做侵入式修改

### 已确认的具体参数

| 项目 | 值 |
|---|---|
| SSH 连接命令 | `et claw-tk1` (使用 Eternal Terminal) |
| MCP 包名 | `@bitbonsai/mcpvault` |
| MCP 仓库 | https://github.com/bitbonsai/mcpvault |
| 锁定版本 | `0.10.0` |
| Vault 路径 | `/home/ubuntu/Autosync/CharlieObsidianVault`（探测修正，原假设 `/home/ubuntu/ObsidianVault` 实为 bare git repo） |
| 安装目录 | `/opt/obsidian-mcp` |
| 本地 MCP 客户端 | Kiro, OpenAI Codex, Gemini CLI（至少） |

---

## 2. 已做出的技术决策

已经确定采用下面这条路线：

**Linux 上的同步 vault 目录 + MCPVault + 本地客户端通过 SSH 启动远端 stdio server**

不要改成下面这些方案，除非遇到明确不可行的阻塞：
- 不要优先改成依赖 Obsidian Local REST API 的方案
- 不要优先改成直接 Google Drive MCP
- 不要默认暴露公网 HTTP MCP endpoint
- 不要引入不必要的常驻服务

---

## 3. 最终成功标准

当任务完成时，应满足以下条件：

1. Linux server 上存在一个清晰的安装目录，例如：
   - `/opt/obsidian-mcp`

2. Linux server 上存在一个清晰的配置文件，例如：
   - `/opt/obsidian-mcp/config.env`

3. Linux server 上存在一个清晰的启动脚本，例如：
   - `/opt/obsidian-mcp/bin/run-mcp.sh`

4. 安装使用**固定版本**的 MCPVault，而不是长期漂移的 `latest`

5. 启动脚本引用的是**实际探测到的 vault 路径**

6. 所有非 vault 的部署文件都放在独立目录，不污染 vault

7. 最终输出一份本地 MCP 客户端可以直接使用的 SSH 配置示例

8. 最终输出一份维护说明文档，例如：
   - `/opt/obsidian-mcp/README.md`

---

## 4. 约束与原则

### 必须遵守

- 优先做**保守且可恢复**的改动
- 尽量保持**幂等**：重复执行不应导致环境混乱
- 所有关键路径都写入 README
- 安装时使用**固定版本**
- 输出中必须明确记录：
  - 选中的 vault 路径
  - 安装的 MCP 包名
  - 安装的版本号
  - 启动命令
  - 本地客户端配置片段

### 不要做的事

- 不要移动 vault
- 不要复制整份 vault 到新位置
- 不要修改 `.obsidian` 配置，除非绝对必要
- 不要默认创建公网监听服务
- 不要默认开放 0.0.0.0 端口
- 不要无理由写入、重命名、删除用户笔记
- 不要把部署文件写到 vault 目录内部
- 不要假设 vault 路径，必须先探测
- 不要把版本写成 `latest` 作为长期配置
- 不要只输出“成功了”，必须输出可核查的结果

---

## 5. 执行风格要求

执行过程中请遵守：

1. 先检查，再改动
2. 每一阶段开始前输出一句正在做什么
3. 每一阶段结束后输出实际结果
4. 对关键命令保留日志或摘要
5. 如果遇到不确定项，优先做探测而不是猜测
6. 如果存在多个 vault 候选路径，进行排序并解释依据
7. 如果无法可靠判断唯一 vault，停止在“待确认”状态，不做危险改动
8. 所有创建的脚本要有注释，并使用清晰命名
9. shell 脚本使用 `set -euo pipefail`

---

## 6. 执行步骤

---

### 阶段 A：远程环境探测

通过 SSH 连接 server，先收集以下信息：

- 当前用户
- 主机名
- 操作系统发行版
- shell
- Node.js 是否已安装
- npm / npx 是否可用
- 是否存在 Google Drive 同步相关进程或已知目录
- 常见候选根路径：
  - `/home`
  - `/srv`
  - `/mnt`
  - `/data`
  - `/var`
- 是否存在包含 `.obsidian` 的目录

建议探测命令思路（可调整）：

```bash
whoami
hostname
uname -a
cat /etc/os-release || true
command -v node || true
node --version || true
command -v npm || true
npm --version || true
command -v npx || true
ps aux | grep -Ei 'google.?drive|drive|grive|rclone' | grep -v grep || true
find /home /srv /mnt /data /var -type d -name .obsidian 2>/dev/null | sed 's#/.obsidian$##'


---

### 阶段 B：验证 Vault 路径

确认 `/home/ubuntu/ObsidianVault` 存在且包含 `.obsidian` 目录：

```bash
ls -la /home/ubuntu/ObsidianVault/.obsidian
ls /home/ubuntu/ObsidianVault/ | head -20
du -sh /home/ubuntu/ObsidianVault
```

如果路径不存在或不包含 `.obsidian`，停止并报告。

---

### 阶段 C：安装 MCPVault

1. 创建安装目录：

```bash
sudo mkdir -p /opt/obsidian-mcp/bin
sudo chown -R $(whoami):$(whoami) /opt/obsidian-mcp
```

2. 在安装目录中初始化 npm 项目并安装固定版本：

```bash
cd /opt/obsidian-mcp
npm init -y
npm install @bitbonsai/mcpvault@0.10.0 --save-exact
```

3. 验证安装：

```bash
ls /opt/obsidian-mcp/node_modules/@bitbonsai/mcpvault/
cat /opt/obsidian-mcp/package.json | grep mcpvault
```

---

### 阶段 D：创建配置与启动脚本

1. 创建 `/opt/obsidian-mcp/config.env`：

```bash
cat > /opt/obsidian-mcp/config.env << 'EOF'
# Obsidian MCP Server 配置
VAULT_PATH=/home/ubuntu/ObsidianVault
MCPVAULT_VERSION=0.10.0
EOF
```

2. 创建 `/opt/obsidian-mcp/bin/run-mcp.sh`：

```bash
cat > /opt/obsidian-mcp/bin/run-mcp.sh << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# Obsidian MCP Server 启动脚本
# 通过 SSH stdio 模式调用，不监听任何端口

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.env"

# 验证 vault 路径存在
if [ ! -d "${VAULT_PATH}" ]; then
  echo "ERROR: Vault path not found: ${VAULT_PATH}" >&2
  exit 1
fi

if [ ! -d "${VAULT_PATH}/.obsidian" ]; then
  echo "WARNING: No .obsidian directory found in ${VAULT_PATH}" >&2
fi

# 使用本地安装的 mcpvault（非 npx latest）
exec "${SCRIPT_DIR}/node_modules/.bin/mcpvault" "${VAULT_PATH}"
SCRIPT

chmod +x /opt/obsidian-mcp/bin/run-mcp.sh
```

3. 测试启动脚本能否正常加载（快速冒烟测试）：

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}' | /opt/obsidian-mcp/bin/run-mcp.sh | head -c 500
```

---

### 阶段 E：生成本地客户端 SSH 配置示例

注意：用户使用 `et claw-tk1`（Eternal Terminal）连接 server。  
但 MCP stdio 模式需要的是标准 SSH（`ssh`），因为 ET 不支持 stdin/stdout 透传给子进程。  
因此客户端配置中使用 `ssh` 而非 `et`。需要确认 server 的 SSH 主机名/别名。

#### Kiro（`.kiro/settings/mcp.json`）

```json
{
  "mcpServers": {
    "obsidian": {
      "command": "ssh",
      "args": ["claw-tk1", "/opt/obsidian-mcp/bin/run-mcp.sh"],
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

#### OpenAI Codex

```json
{
  "mcpServers": {
    "obsidian": {
      "command": "ssh",
      "args": ["claw-tk1", "/opt/obsidian-mcp/bin/run-mcp.sh"]
    }
  }
}
```

#### Gemini CLI

```bash
gemini mcp add obsidian -- ssh claw-tk1 /opt/obsidian-mcp/bin/run-mcp.sh
```

> **待确认**：`claw-tk1` 是否也是你 `~/.ssh/config` 中的 SSH Host 别名？如果 ET 和 SSH 用的不是同一个别名，需要你提供 SSH 的主机名或别名。

---

### 阶段 F：生成维护文档

在 `/opt/obsidian-mcp/README.md` 中记录：

- 部署日期
- Vault 路径
- 包名与版本
- 启动命令
- 升级方法（`npm install @bitbonsai/mcpvault@<新版本> --save-exact`）
- 客户端配置片段
- 故障排查要点

---

## 7. 待确认事项

在执行前需要用户确认：

- [ ] `claw-tk1` 是否同时也是 `~/.ssh/config` 中的 SSH Host？如果不是，MCP 客户端用什么 SSH 主机名连接？
- [ ] server 上 Node.js 是否已安装？版本是否 >= 18？
- [ ] 当前用户是否有 `sudo` 权限（用于创建 `/opt/obsidian-mcp`）？
- [ ] 是否需要支持多 vault？当前只配置 `/home/ubuntu/ObsidianVault` 一个。

### 阶段 A：远程环境探测 ✅ 已完成

执行日期：2026-03-23

#### 探测结果

| 项目 | 结果 |
|---|---|
| 用户 | `ubuntu` |
| 主机名 | `ip-172-26-9-198` |
| 系统 | Ubuntu 22.04.5 LTS (Jammy Jellyfish), Linux 6.8.0-1047-aws x86_64 |
| Node.js | ✅ v22.22.0 (`/usr/bin/node`) |
| npm | ✅ 10.9.4 (`/usr/bin/npm`) |
| npx | ✅ 可用 |
| Google Drive 同步进程 | 未检测到运行中的进程（可能是 cron/systemd 定时同步） |
| sudo | ✅ 可用（无密码） |

#### Vault 路径探测

```bash
find /home/ubuntu -maxdepth 4 -type d -name .obsidian 2>/dev/null
```

结果：

```
/home/ubuntu/Autosync/CharlieObsidianVault/.obsidian
```

> ⚠️ 用户原始提供的路径 `/home/ubuntu/ObsidianVault` 实际是一个 bare git repo（包含 HEAD, objects, refs 等），不是 Obsidian vault。  
> 实际 vault 位于 `/home/ubuntu/Autosync/CharlieObsidianVault`，大小 236M。

---

### 阶段 B：验证 Vault 路径 ✅ 已完成

```bash
ls /home/ubuntu/Autosync/CharlieObsidianVault/ | head -20
```

确认包含典型 vault 内容：`Archive`, `Assets`, `Life`, `Work`, `Wiki`, `_index`, `knowledge` 等目录和 `.md` 文件。  
`.obsidian` 目录存在。大小 236M。

---

### 阶段 C：安装 MCPVault ✅ 已完成

```bash
sudo mkdir -p /opt/obsidian-mcp/bin
sudo chown -R ubuntu:ubuntu /opt/obsidian-mcp
cd /opt/obsidian-mcp
npm init -y
npm install @bitbonsai/mcpvault@0.10.0 --save-exact
```

结果：

```
added 102 packages, and audited 103 packages in 26s
found 0 vulnerabilities
```

验证：

```
/opt/obsidian-mcp/node_modules/.bin/mcpvault -> ../@bitbonsai/mcpvault/dist/server.js
package.json: "@bitbonsai/mcpvault": "0.10.0"
```

---

### 阶段 D：创建配置与启动脚本 ✅ 已完成

#### config.env

```
# Obsidian MCP Server 配置
# 部署日期: 2026-03-23
VAULT_PATH=/home/ubuntu/Autosync/CharlieObsidianVault
MCPVAULT_VERSION=0.10.0
```

#### bin/run-mcp.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# Obsidian MCP Server 启动脚本
# 通过 SSH stdio 模式调用，不监听任何端口
# 部署日期: 2026-03-23

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.env"

if [ ! -d "${VAULT_PATH}" ]; then
  echo "ERROR: Vault path not found: ${VAULT_PATH}" >&2
  exit 1
fi

if [ ! -d "${VAULT_PATH}/.obsidian" ]; then
  echo "WARNING: No .obsidian directory found in ${VAULT_PATH}" >&2
fi

exec "${SCRIPT_DIR}/node_modules/.bin/mcpvault" "${VAULT_PATH}"
```

#### 冒烟测试

```bash
{ echo '{"jsonrpc":"2.0","id":1,"method":"initialize",...}'; sleep 2; } | /opt/obsidian-mcp/bin/run-mcp.sh
```

响应：

```json
{"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"mcpvault","version":"0.10.0"}},"jsonrpc":"2.0","id":1}
```

✅ MCP server 正常启动，返回 mcpvault 0.10.0，协议版本 2024-11-05。

---

### 阶段 E：本地客户端 SSH 配置示例 ✅ 已完成

SSH 别名 `claw-tk1` 已验证可用于 `ssh claw-tk1` 命令。

#### Kiro（`.kiro/settings/mcp.json`）

```json
{
  "mcpServers": {
    "obsidian": {
      "command": "ssh",
      "args": ["-o", "RequestTTY=no", "claw-tk1", "/opt/obsidian-mcp/bin/run-mcp.sh"],
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

#### OpenAI Codex

```json
{
  "mcpServers": {
    "obsidian": {
      "command": "ssh",
      "args": ["-o", "RequestTTY=no", "claw-tk1", "/opt/obsidian-mcp/bin/run-mcp.sh"]
    }
  }
}
```

#### Gemini CLI

```bash
gemini mcp add obsidian -- ssh -o RequestTTY=no claw-tk1 /opt/obsidian-mcp/bin/run-mcp.sh
```

> 注意：加了 `-o RequestTTY=no` 避免 shell rc 中的 `set-title` 等 TTY 相关命令干扰 stdio 通信。

---

### 阶段 F：维护文档 ✅ 已完成

已在远端创建 `/opt/obsidian-mcp/README.md`，包含基本信息、启动命令、升级方法和故障排查。

---

## 7. 部署结果总览

| 成功标准 | 状态 |
|---|---|
| 安装目录 `/opt/obsidian-mcp` | ✅ |
| 配置文件 `config.env` | ✅ |
| 启动脚本 `bin/run-mcp.sh` | ✅ |
| 固定版本 `0.10.0` | ✅ |
| 实际探测的 vault 路径 | ✅ `/home/ubuntu/Autosync/CharlieObsidianVault` |
| 部署文件与 vault 隔离 | ✅ |
| 客户端 SSH 配置示例 | ✅ Kiro / Codex / Gemini CLI |
| 远端 README.md | ✅ |
| 冒烟测试通过 | ✅ |

## 8. 远端文件清单

```
/opt/obsidian-mcp/
├── bin/
│   └── run-mcp.sh          # 启动脚本
├── config.env               # 配置（vault 路径、版本号）
├── package.json             # npm 项目（锁定依赖版本）
├── package-lock.json        # npm 锁文件
├── node_modules/            # @bitbonsai/mcpvault@0.10.0
└── README.md                # 维护说明
```

## 9. 下一步

- [ ] 在 Kiro 中配置 `.kiro/settings/mcp.json` 并测试连接
- [ ] 在 Gemini CLI / Codex 中配置并测试
- [ ] 确认 Google Drive 同步是否仍在正常工作（未检测到运行中进程，可能需要检查 cron 或 systemd）
