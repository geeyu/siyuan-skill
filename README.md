# siyuan — 思源笔记 skill

基于 [SiYuan-Kernel 3.8+](https://github.com/siyuan-note/siyuan) 内置 CLI 的 **shell 风格命令封装**，让 AI agent（和人类）像操作 Linux 一样操作思源笔记：`ls` 列文档、`cat` 读内容、`grep` 全文检索、`find` 搜文档、`which` 定位、`sql` 查询、管道组合。

## 安装

skill 已放在 `~/.pi/skills/siyuan/`，pi 会自动发现。终端直接用可加 alias：

```bash
echo 'alias siyuan=~/.pi/skills/siyuan/bin/siyuan' >> ~/.zshrc
```

## 渐进式加载设计

遵循 [Agent Skills 标准](https://agentskills.io/specification) 的 progressive disclosure：

- **SKILL.md** (入口): 常用命令速查 + 核心约定 + 典型用法。pi 启动时只加载 frontmatter 的 description, 匹配任务时才 read 全文。
- **references/** (按需加载):
  - `commands.md` — 完整底层命令参考 (24 类命令)
  - `database.md` — 数据库(AV) 完整规范
  - `conventions.md` — 详细约定与源码依据
- **scripts/av_ops.js** — 数据库(AV) 操作工具库
- **bin/siyuan** — CLI 封装层 (bash 框架 + node 数据层):
  - `bin/lib/framework.sh` — 命令注册表 / 内核调用(超时) / 统一错误与退出码 / JSON 助手
  - `bin/lib/cmd-query.sh` — 查询命令组 (ls/tree/cat/head/tail/find/grep/which/stat)
  - `bin/lib/cmd-misc.sh` — sql/raw/raw-help/children/backlinks
  - `bin/lib/cmd-write.sh` — write/append/insert-block/update-block/delete-block/replace-doc/move/remove
  - `bin/lib/fmt.js` — node 数据格式化助手 (JSON→TSV/文本/稳定字段)

## 配置

默认值适合本机，可通过环境变量覆盖：

| 变量 | 默认 | 说明 |
|------|------|------|
| `SIYUAN_KERNEL` | `/Applications/SiYuan.app/Contents/Resources/kernel/SiYuan-Kernel` | 内核二进制路径 |
| `SIYUAN_WORKSPACE` | `/Users/geeyu/space/siyuan` | 工作区路径 |
| `SIYUAN_FORMAT` | `text` | 默认输出格式 (`json` = 默认开 `--json`) |
| `SIYUAN_TIMEOUT` | `60` | 内核调用超时秒数 (0=不超时, 超时退出码 124) |
| `SIYUAN_DEFAULT_NOTEBOOK` | 空 | 设置后无参 `ls` 列该笔记本文档 |
| `SIYUAN_API_HOST` / `SIYUAN_API_PORT` | `127.0.0.1` / `6806` | 内核 HTTP API (写入兜底) |

依赖: `bash 3.2+` / `node 18+` (PATH、fnm、brew 自动兜底定位)。

## 常用命令

```bash
siyuan ls                               # 列笔记本
siyuan ls 工作                          # 列笔记本下文档 (支持中文名)
siyuan cat <doc-id>                     # 读文档 markdown
siyuan head <doc> -n 20                 # 读开头 20 行
siyuan find "关键词"                    # 搜文档
siyuan grep "内容关键词"                # 内容全文检索
siyuan grep -m 3 "正则"                 # 正则检索
siyuan which 标题                       # 定位文档 → doc id
siyuan stat <doc>                       # 文档元信息
siyuan sql "SELECT ..."                 # SQL 查询
siyuan write --notebook 工作 --title "T" --parent-id <pid>   # 建文档
siyuan raw database search "库名"       # 底层透传 (见 references/database.md)
```

组合 (管道):
```bash
siyuan ls 工作 | siyuan grep 调课        # 过滤文档列表
siyuan cat $(siyuan which /工作/调课)    # 定位并读文档
siyuan grep --content 调课 -l | head -5  # 内容命中前 5 篇文档
```

## 退出码契约

| 码 | 含义 |
|----|------|
| 0 | 成功 |
| 1 | 业务/运行时错误 (找不到文档/笔记本、SQL 错误、无匹配) |
| 2 | 用法错误 (缺参数、未知参数) |
| 3 | 配置错误 (内核/工作区/node 缺失) |
| 124 | 内核调用超时 |

错误写 stderr, 格式 `siyuan <命令>: <原因>` + 建议行。所有查询命令支持 `--json` 输出稳定字段。

## 思源源码

行为依据可查本地源码：`/Users/geeyu/space/code/github/siyuan`

关键文件：
- `kernel/cli/cmd/*.go` — CLI 命令实现
- `kernel/av/value.go` — AV 数据库值结构体
- `kernel/model/attribute_view.go` — AV 数据库逻辑
- `kernel/model/file.go` — 文档操作 (RenameDoc 等)

详见 SKILL.md。
