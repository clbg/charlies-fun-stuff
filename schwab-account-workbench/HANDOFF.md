---
title: Schwab Dashboard 工作交接 / 进度
created: 2026-07-15
updated: 2026-07-16
type: project
tags:
  - schwab-dashboard
  - handoff
---

# Schwab Dashboard 交接文档

代码目录：`~/projects/charlies-fun-stuff/schwab-account-workbench/`  
数据目录：`Investment/Portfolio/SchwabHistory/`

## 当前结构

```text
apps/dashboard/          React + TypeScript + ECharts dashboard
src/schwab_workbench/    Schwab API auth/refresh/smoke/publish pipeline
docs/                    schema and historical notes
```

Vault 只保留私有数据和发布产物，不再维护前端/管线源码。

## 常用命令

```bash
cd ~/projects/charlies-fun-stuff/schwab-account-workbench
mise run refresh     # API -> vault viewer/data.js + DuckDB + processed JSON
mise run build       # build apps/dashboard/dist/index.html
mise run publish     # copy built dashboard into the vault artifact path
mise run open        # build and open local dashboard
mise run dev         # Vite dev server
mise run test        # typecheck + vitest
```

## 数据流

```text
Schwab Trader API
  -> src/schwab_workbench/api_refresh.py
  -> Investment/Portfolio/SchwabHistory/viewer/data.js
  -> apps/dashboard/scripts/dataToJson.mjs
  -> apps/dashboard/src/data/portfolio.json
  -> apps/dashboard/dist/index.html
```

## 已知约束

- 当前持仓、余额、未实现盈亏以 Schwab Trader API 的 `account_snapshots` 和
  `position_snapshots` 为准。
- 完整历史交易、现金流、股息、费用仍依赖归档 CSV/processed 文件，因为 Schwab API 的
  transaction history 是近窗口数据。
- `src/schwab_workbench/build_history_db.py` 是旧 CSV fallback；不要用它覆盖 live
  viewer，除非明确要回退旧 schema。
- 所有源码改动只做在 funstuff 项目；vault 内的 `viewer-react/dist/index.html` 是发布产物。
- 数据源、key 名称和降级策略统一维护在 `docs/data-sources.md`。
