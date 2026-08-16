# siyuan — 思源笔记 skill

基于 [SiYuan-Kernel 3.8+](https://github.com/siyuan-note/siyuan) 内置 CLI 的 **shell 风格命令封装**, 让 AI agent (和人类) 像操作 Linux 一样操作思源笔记: `ls` 列文档、`cat` 读内容、`grep` 全文检索、`find` 搜文档、`which` 定位、`sql` 查询、管道组合。

## 安装

skill 已放在 `~/.pi/skills/siyuan/`, pi 会自动发现。终端直接用可加 alias:

```bash
echo 'alias siyuan=~/.pi/skills/siyuan/bin/siyuan' >> ~/.zshrc
```

## 结构 (渐进式)

遵循 [Agent Skills 标准](https://agentskills.io/specification) 的 progressive disclosure:

```
SKILL.md (入口)                 引用协议 + 命令速查 + 高频坑 → 立刻能干活
  ↓ 需要命令细节
references/commands.md          ★ 封装命令完整参考 (参数/输出/示例/组合)
  ↓ 封装不满足
references/raw.md               底层原始命令 (24 类, 或 raw-help 实时查)
  ↓ 复杂功能
references/database.md          数据库 (AV) 深度规范
  ↓ 踩坑沉淀
references/conventions.md       批量整理等事故规范
```

**实现** (使用者无需关心):

- `bin/siyuan` — CLI 主入口 (bash 框架 + node 数据层):
  - `bin/lib/framework.sh` — 引用解析器 / 内核调用 (超时) / 统一错误与退出码
  - `bin/lib/cmd-query.sh` — 查询命令组 (ls/tree/cat/head/tail/find/grep/which/stat)
  - `bin/lib/cmd-misc.sh` — sql/raw/raw-help/children/backlinks
  - `bin/lib/cmd-write.sh` — 底层写入组 (write/append/insert-block/update-block/delete-block/replace-doc/move/remove)
  - `bin/lib/cmd-edit.sh` — shell 风格编辑组 (touch/edit/mv/cp/rm/diff/rename)
  - `bin/lib/cmd-av.sh` — av 命令组 (适配 3.8.0 B1/B2)
  - `bin/lib/fmt.js` — node 数据格式化助手
- `scripts/smoke-markdown.sh` — 开发自测冒烟脚本

## 配置

默认值适合本机, 可通过环境变量覆盖:

| 变量 | 默认 | 说明 |
| ------ | ------ | ------ |
| `SIYUAN_KERNEL` | `/Applications/SiYuan.app/Contents/Resources/kernel/SiYuan-Kernel` | 内核二进制路径 |
| `SIYUAN_WORKSPACE` | `/Users/geeyu/space/siyuan` | 工作区路径 |
| `SIYUAN_FORMAT` | `text` | 默认输出格式 (`json` = 默认开 `--json`) |
| `SIYUAN_TIMEOUT` | `60` | 内核调用超时秒数 (0=不超时, 超时退出码 124) |
| `SIYUAN_DEFAULT_NOTEBOOK` | 空 | 设置后无参 `ls` 列该笔记本文档 |
| `SIYUAN_API_HOST` / `SIYUAN_API_PORT` | `127.0.0.1` / `6806` | 内核 HTTP API (建文档兜底) |

依赖: `bash 3.2+` / `node 18+` (PATH、fnm、brew 自动兜底定位)。

## 引用协议 (30 秒)

所有命令的文档引用统一: **id | 路径 | 标题**, 路径必须真实存在 (不存在即报错), 模糊用显式通配 `/*/xxx` (`*` 任意层级含零层, `?` 单字符), 标题多匹配列候选报错。详见 SKILL.md「引用协议」。

## 常用命令

```bash
siyuan ls                               # 列笔记本
siyuan ls 工作                          # 列笔记本下文档 (支持中文名)
siyuan ls /工作/日志/2026/AI伴学          # 列目录 (路径必须真实)
siyuan ls "/*/AI伴学"                    # 通配: 任意层级
siyuan cat <doc>                        # 读文档 markdown
siyuan head <doc> -n 20                 # 读开头 20 行
siyuan find "关键词"                    # 搜文档标题
siyuan grep "内容关键词"                # 内容全文检索 (管道输入时按行过滤)
siyuan which 标题                       # 定位文档 → doc id
siyuan stat <doc>                       # 文档元信息
siyuan sql "SELECT ..."                 # SQL 查询
siyuan touch --notebook 工作 --title "T" --parent <父文档>   # 建文档 (推荐)
siyuan edit <doc> --append "内容"       # 追加 (--prepend/--update/--replace)
siyuan rename <doc> "新标题"            # 改名 (IAL + H1 同步, 重名预检)
siyuan mv <doc> --parent <父文档>        # 移动 (同/跨笔记本, 别名 --to)
siyuan cp <doc> --parent <父文档>        # 复制
siyuan diff <docA> <docB>               # 对比两文档 (统一 diff)
siyuan rm <doc>                         # 删除
siyuan av list                          # 数据库列表 (见 references/database.md)
siyuan raw database search "库名"       # 底层透传
```

组合 (管道):

```bash
siyuan ls 工作 | siyuan grep 调课        # 过滤文档列表
siyuan cat $(siyuan which /工作/调课)    # 定位并读文档
siyuan grep 调课 -l | head -5            # 内容命中前 5 篇文档
```

## 退出码契约

| 码 | 含义 |
| ---- | ------ |
| 0 | 成功 |
| 1 | 业务/运行时错误 (找不到文档/笔记本、SQL 错误、无匹配、歧义) |
| 2 | 用法错误 (缺参数、未知参数) |
| 3 | 配置错误 (内核/工作区/node 缺失) |
| 124 | 内核调用超时 |

错误写 stderr, 格式 `siyuan <命令>: <原因>` + 建议行。所有查询命令支持 `--json` 输出稳定字段。

## 思源源码

行为依据可查本地源码: `/Users/geeyu/space/code/github/siyuan`

关键文件:

- `kernel/cli/cmd/*.go` — CLI 命令实现
- `kernel/av/value.go` — AV 数据库值结构体
- `kernel/model/attribute_view.go` — AV 数据库逻辑
- `kernel/model/file.go` — 文档操作 (RenameDoc 等)

详见 SKILL.md。
