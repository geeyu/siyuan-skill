---
name: siyuan
description: >
  思源笔记 (SiYuan) 命令行操作能力。当用户提到 思源、笔记、siyuan、写入笔记、
  查笔记、搜文档、记到笔记里、整理成笔记、数据库、属性视图、排查记录库、字段、AV
  等场景时触发。提供笔记本/文档/块/SQL/数据库(AV) 全套读写能力。基于 SiYuan-Kernel 3.8+ CLI 封装。
---

# siyuan — 思源笔记操作 skill

## 文档导航 (渐进式)

| 层 | 文档 | 什么时候读 |
| ---- | ------ | ----------- |
| 入口 | **本文 (SKILL.md)** | 立刻开始干活: 引用协议 + 速查 + 约定 |
| 详情 | [references/commands.md](references/commands.md) | 封装命令的完整参数/输出/示例/组合 (含数据库 db 命令组) |
| 底层 | [references/raw-commands.md](references/raw-commands.md) | 封装满足不了时, 原始内核命令 (或 `siyuan raw-help <cmd>` 实时查) |
| 踩坑 | [references/conventions.md](references/conventions.md) | 批量整理等事故规范 |

## 何时使用

用户想把内容写进思源笔记、查询思源里的笔记、或对思源做批量操作时使用。典型场景:

- "把这个分析整理成笔记" / "记到思源里"
- "查一下我思源里关于 X 的笔记"
- "在 XX 笔记本下建一篇文档" / "给那篇笔记追加一段内容"
- 录入结构化数据到数据库 (排查记录、台账等)
- 批量整理文档 (移动/重命名/建目录) → 先读 [conventions.md](references/conventions.md) §14

## 入口

```bash
~/.pi/skills/siyuan/bin/siyuan <command> [args]
```

shell 风格命令集 (像操作 Linux 一样操作思源): 默认人类可读文本 (行式可管道组合), `--json` 输出稳定字段 (agent 用), `--markdown` 输出笔记格式。工作区 `/Users/geeyu/space/siyuan` (可被 `SIYUAN_WORKSPACE` 覆盖)。

## 引用协议 (最重要, 全部命令统一)

**所有命令的文档引用 `<doc>` 遵循同一规则, Linux 直觉, 无需学习私有协议:**

| 形式 | 示例 | 规则 |
| ------ | ------ | ------ |
| id | `20260727201107-6cawv5h` | 精确命中 |
| 完整路径 | `/工作/日志/2026/AI伴学` (或 `工作/日志/...` 无前导 /) | 必须真实存在, **不存在即报错** |
| hpath | `/日志/2026/AI伴学` (无笔记本名) | 精确匹配 |
| 通配 (显式模糊) | `/*/AI伴学`、`/工作/*/调课` | `*` 任意层级 (含零层), `?` 单字符; 多命中为正常结果 |
| 标题 | `AI伴学` (无 `/`) | 精确同名优先, **多匹配列出候选并报错** (防误操作) |

- 路径输出统一为 `/笔记本/目录…/标题` (带前导 `/`), find/grep/which -v/候选列表一致, 可直接喂回
- 块引用 (`children`/`backlinks`/`insert-block --parent`) 接受块 id 或文档引用 (自动定位到文档根块)
- 歧义一律列候选报错, 绝无静默选中

## 命令速查 (完整参考见 commands.md)

### 读取

| 命令 | 作用 |
| ------ | ------ |
| `ls [引用] [-l]` | 列笔记本/文档; 空=列笔记本, 叶子文档显示自身, 通配 `/*/xxx` |
| `tree <doc>` | 标题树 (无标题文档输出空) |
| `cat <doc>` | 读 markdown 源 (最准, 写入验证首选) |
| `head/tail <doc> [-n N]` | 读开头/末尾 N 行 (默认 10) |
| `find <关键词> [--notebook <nb>]` | 搜文档标题 → `id<TAB>完整路径<TAB>notebook` |
| `grep <pattern> [-v] [-i] [-m 0-3]` | 内容全文检索; 管道输入时按行过滤 (`ls 工作 \| grep 调课`) |
| `which <引用> [-v]` | 定位 → 唯一 doc id (多匹配列候选) |
| `stat <doc>` | 文档元信息 |
| `sql "<语句>" [-l N] [-H]` | SQL 查询 (默认 limit 100) |
| `children <block\|doc>` | 子块列表 (编辑前定位块 id) |
| `backlinks <block\|doc> [--keyword]` | 反链 |

### 写入/编辑 (每次写操作返回目标 id)

| 命令 | 作用 |
| ------ | ------ |
| `touch --notebook <nb> --title <t> [--parent <父文档>\|--path <hpath>]` | 建文档 (推荐) |
| `edit <doc> (--append\|--prepend\|--update <块id>\|--replace) <text>` | 统一编辑: 追加/插入/改块/替换 |
| `mv <doc> --parent <父文档> [--notebook <nb>]` | 移动 (同/跨笔记本; 别名 --to) |
| `cp <doc> [--parent <父文档>]` | 复制 (别名 --to) |
| `rm <doc>` | 删除 (⚠ 删目录级联删子文档) |
| `diff <docA> <docB> [diff 参数...]` | 对比 (rc: 0=同 1=异) |
| `rename <doc> <新标题>` | 改名 (IAL+H1 同步, 同目录重名预检) |

内容传入统一支持 `--data <字符串>` / `--file <文件>` / 管道 stdin; 引用统一支持 id/标题/路径。

### 数据库 (AV) — 完整参考见 commands.md「四、数据库」

```bash
siyuan db list                          # 全部数据库
siyuan db rows <avID> [--limit N]       # 行数据
siyuan db add <avID> --values '<JSON>' [--content 标题] [--block <doc>]   # 加行
siyuan db update <avID> --row <行ID> --values '<JSON>'                    # 改行
siyuan db verify <avID>                 # 验证 (权威入口, item update 的 ok 不可信)
siyuan db export <avID>                 # 备份
```

### 底层透传 (封装满足不了时)

```
siyuan raw <args...>       # 透传 SiYuan-Kernel (24 类命令见 raw-commands.md)
siyuan raw-help <sub...>   # 查底层帮助, 例: raw-help block insert
```

## 核心约定 (高频必读)

1. **创建文档优先用 `--parent`**: 封装已自动处理 createDocWithMd 中间块问题 (三步语义); `--parent` 引用支持 id/标题/路径。
2. **判断写入成功看 `cat`, 不看 SQL**: block 写后 SQL 查 `content` 可能滞后 (秒级), `cat` 读文件是准的。
3. **文档名由 IAL `title` 决定, 不是 H1**: `rename` 自动同步两者; ⚠ 不要对文档块本身做 `block update` (会把整篇内容替换掉)。
4. **notebook 参数支持中文名**: `siyuan ls 工作`; 设 `SIYUAN_DEFAULT_NOTEBOOK` 后无参 `ls` 列该库。
5. **mv/move、cp 同/跨笔记本都适用**: 自动取父文档所在笔记本。
6. **rename 有同目录重名预检**: 改出的新标题与同父级已有文档重名 → 报错。
7. **不知道参数时**: `siyuan raw-help <command>` 查帮助, 不要猜。
8. **退出码**: 0=成功 1=业务错误 2=用法错误 3=配置错误 124=超时; `diff` 例外 (0=同 1=异)。
9. **批量整理文档 (⚠ 高频事故区)**: ① `rm <目录>` 级联删除全部子文档 — 先移出再删; ② 同名文档很常见, 批量循环**用 id 不用标题**; ③ rename/建目录前先 `find` 预检重名。详见 conventions.md §14。

## 典型用法

### 1. 写一篇笔记 (touch + --parent)

```bash
PARENT=$(siyuan which /工作/调课)     # 定位父文档 (同名用完整路径)
cat <<'EOF' | siyuan touch --notebook 工作 --title "调课逻辑梳理" --parent "$PARENT"
# 调课逻辑

## 入口
...
EOF
```

### 2. 搜 + 读

```bash
siyuan find "调课"            # id<TAB>完整路径<TAB>notebook
DOC=$(siyuan which 调课)       # 多匹配时报错列候选
siyuan cat "$DOC" && siyuan tree "$DOC"
```

### 3. 编辑

```bash
siyuan edit "$DOC" --append "## 新章节"          # 追加
BID=$(siyuan children "$DOC" | awk -F'\t' '$2=="p"{print $1;exit}')
siyuan edit "$DOC" --update "$BID" "新内容"       # 改块
siyuan rename "$DOC" "新文档名"
siyuan mv "$DOC" --parent "$(siyuan which /目标目录)"
```

### 4. 通配与管道

```bash
siyuan ls "/*/AI伴学"              # 任意笔记本下的 AI伴学
siyuan ls 工作 | siyuan grep 调课   # 过滤
siyuan cat $(siyuan which /工作/调课)
```

### 5. 批量整理

```bash
ls /AI伴学/待办实现 | while read -r id name; do siyuan mv "$id" --parent <目标>; done
# ⚠ 用 id 循环 (标题可能歧义中断整批); 删目录前先移出全部子文档
```

## 故障排查

- **"找不到内核二进制"**: 装 SiYuan.app 或设 `SIYUAN_KERNEL`
- **"工作区不存在"**: 设 `SIYUAN_WORKSPACE`
- **思源没启动**: CLI 直接操作工作区文件, 不需要 App; App 开着时操作后刷新
- **Unknown flag**: `siyuan raw-help <command>` 查最新参数
- **SQL 查到旧数据**: 索引滞后, `sleep 2-3` 重试, 或 `cat` 验证
- **引用报"找不到"**: 路径必须完整真实; 模糊用通配 `/*/xxx`; 记不清用 `find` 搜标题
- **引用报"有 N 个匹配"**: 同名歧义, 用完整路径消歧或 `-v` 看候选
- **数据库写入不生效**: `siyuan db verify` 验证 (item update 的 ok 不可信)

## 工作区信息

- 内核: `/Applications/SiYuan.app/Contents/Resources/kernel/SiYuan-Kernel` (v3.8.0)
- 工作区: `/Users/geeyu/space/siyuan`
- 笔记本: 工作 / 学习 / 生活
- 思源源码 (查行为依据): `/Users/geeyu/space/code/github/siyuan`
