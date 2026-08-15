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
- **scripts/av_ops.js** — 数据库(AV) 旧工具库 (能力已迁移至 `siyuan av` 命令组, 保留供旧脚本引用)
- **bin/siyuan** — CLI 封装层 (bash 框架 + node 数据层):
  - `bin/lib/framework.sh` — 命令注册表 / 内核调用(超时) / 统一错误与退出码 / JSON 助手
  - `bin/lib/cmd-query.sh` — 查询命令组 (ls/tree/cat/head/tail/find/grep/which/stat)
  - `bin/lib/cmd-misc.sh` — sql/raw/raw-help/children/backlinks
  - `bin/lib/cmd-write.sh` — 底层写入 (write/append/insert-block/update-block/delete-block/replace-doc/move/remove) + 共享写入助手
  - `bin/lib/cmd-edit.sh` — shell 风格编辑命令组 (touch/edit/mv/cp/rm/diff/rename)
  - `bin/lib/cmd-av.sh` — av 命令组 (list/keys/rows/get/add/update/remove/verify/export, 适配 3.8.0 B1/B2)
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

## 输出模式

全部命令三种输出模式 (三选一, `--json` 与 `--markdown` 互斥):

| 模式 | 说明 | 用途 |
|------|------|------|
| 默认 | 人类可读文本, 行式可管道组合 | 终端/管道 |
| `--json` | 稳定字段 JSON (可被 `SIYUAN_FORMAT=json` 全局默认开启) | agent 解析 |
| `--markdown` | 表格/嵌套列表/确认块; **stdout 只含 markdown**, 可直接重定向 `.md` 或粘贴进思源, 错误仍走 stderr | 笔记内容/文件 |

```bash
siyuan ls 工作 --markdown > 目录.md                          # 文档列表 → markdown 表格
siyuan sql "SELECT id, hpath FROM blocks LIMIT 5" --markdown  # SQL → 表格 (含表头分隔行)
siyuan tree <doc> --markdown                                 # 标题树 → 嵌套无序列表
siyuan write --notebook 工作 --title "T" --parent-id <pid> --markdown  # 确认块 (id+标题+链接)
```

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
```

旧命令名 `notebooks/nb/list/read/get/outline/search/create/bl/rm` 保留为别名; 计划命名 (touch/edit/mv/cp/diff/rename/av) 与实现命令的对应关系见 SKILL.md 与 references/commands.md。

组合 (管道):
```bash
siyuan ls 工作 | siyuan grep 调课        # 过滤文档列表
siyuan cat $(siyuan which /工作/调课)    # 定位并读文档
siyuan grep --content 调课 -l | head -5  # 内容命中前 5 篇文档
siyuan ls 工作 --markdown | siyuan grep 调课 --markdown  # markdown 表格行过滤
```

## 退出码契约

| 码 | 含义 |
|----|------|
| 0 | 成功 |
| 1 | 业务/运行时错误 (找不到文档/笔记本、SQL 错误、无匹配) |
| 2 | 用法错误 (缺参数、未知参数) |
| 3 | 配置错误 (内核/工作区/node 缺失) |
| 124 | 内核调用超时 |

错误写 stderr, 格式 `siyuan <命令>: <原因>` + 建议行。查询命令支持 `--json` / `--markdown` 输出 (互斥), 写命令支持 `--markdown` 确认块 / `--json` 稳定字段。

## 思源源码

行为依据可查本地源码：`/Users/geeyu/space/code/github/siyuan`

关键文件：
- `kernel/cli/cmd/*.go` — CLI 命令实现
- `kernel/av/value.go` — AV 数据库值结构体
- `kernel/model/attribute_view.go` — AV 数据库逻辑
- `kernel/model/file.go` — 文档操作 (RenameDoc 等)

详见 SKILL.md。
