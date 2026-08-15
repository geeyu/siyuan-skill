# siyuan — 思源笔记 skill

基于 [SiYuan-Kernel 3.7+](https://github.com/siyuan-note/siyuan) 内置 CLI 的封装，让 AI agent（和人类）能稳定地操作思源笔记：建文档、搜笔记、读内容、追加内容、SQL 查询、数据库(AV)。

## 安装

skill 已放在 `~/.pi/skills/siyuan/`，pi 会自动发现。终端直接用可加 alias：

```bash
echo 'alias siyuan=~/.pi/skills/siyuan/bin/siyuan' >> ~/.zshrc
```

## 渐进式加载设计

遵循 [Agent Skills 标准](https://agentskills.io/specification) 的 progressive disclosure：

- **SKILL.md** (入口, ~160 行): 常用命令速查 + 核心约定 + 典型用法。pi 启动时只加载 frontmatter 的 description, 匹配任务时才 read 全文。
- **references/** (按需加载):
  - `commands.md` — 完整底层命令参考 (18 类命令: notebook/document/block/attr/bookmark/tag/dailynote/file/export/import/asset/history/inbox/template/repo/sync/system/workspace)
  - `database.md` — 数据库(AV) 完整规范 (值结构对照表、录入流程、坑点根因)
  - `conventions.md` — 详细约定与源码依据
- **scripts/verify_av.py** — 数据库字段值验证脚本
- **bin/siyuan** — CLI 封装层 (bash)

这样"写笔记"等简单任务只加载精简 SKILL.md，操作数据库时才加载完整规范，节省 context。

## 配置

默认值适合本机，可通过环境变量覆盖：

| 变量 | 默认 | 说明 |
|------|------|------|
| `SIYUAN_KERNEL` | `/Applications/SiYuan.app/Contents/Resources/kernel/SiYuan-Kernel` | 内核二进制路径 |
| `SIYUAN_WORKSPACE` | `/Users/geeyu/space/siyuan` | 工作区路径 |
| `SIYUAN_API_PORT` | `6806` | 内核 HTTP API 端口 |
| `SIYUAN_FORMAT` | `json` | 默认输出格式 |

## 常用命令

```bash
siyuan notebooks                        # 列笔记本
siyuan search "关键词"                   # 搜文档
siyuan write --notebook 工作 --title "T" --parent-id <pid>  # 建文档
siyuan read <doc-id>                    # 读文档
siyuan sql "SELECT ..."                 # SQL 查询
siyuan raw database search "库名"        # 数据库操作 (见 references/database.md)
```

## 思源源码

行为依据可查本地源码：`/Users/geeyu/space/code/github/siyuan`

关键文件：
- `kernel/cli/cmd/*.go` — CLI 命令实现
- `kernel/av/value.go` — AV 数据库值结构体
- `kernel/model/attribute_view.go` — AV 数据库逻辑
- `kernel/model/file.go` — 文档操作 (RenameDoc 等)

详见 SKILL.md。
