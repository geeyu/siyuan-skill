---
name: siyuan
description: >
  思源笔记 (SiYuan) 命令行操作能力。当用户提到 思源、笔记、siyuan、写入笔记、
  查笔记、搜文档、记到笔记里、整理成笔记、数据库、属性视图、排查记录库、字段、AV
  等场景时触发。提供笔记本/文档/块/SQL/数据库(AV) 全套读写能力。基于 SiYuan-Kernel 3.8+ CLI 封装。
---

# siyuan — 思源笔记操作 skill

## 何时使用

用户想把内容写进思源笔记、查询思源里的笔记、或对思源做批量操作时使用。典型场景:

- "把这个分析整理成笔记" / "记到思源里"
- "查一下我思源里关于 X 的笔记"
- "在 XX 笔记本下建一篇文档" / "给那篇笔记追加一段内容"
- 录入结构化数据到数据库 (排查记录、台账等) → 见 [references/database.md](references/database.md)
- 批量整理文档 (移动/重命名/建目录) → 见 [references/conventions.md](references/conventions.md) §14

## 入口

```bash
~/.pi/skills/siyuan/bin/siyuan <command> [args]
```

shell 风格命令集 (类似 Linux 命令操作思源笔记): 默认人类可读文本 (行式可管道组合), `--json` 输出稳定字段 (agent 用), `--markdown` 输出笔记格式。工作区 `/Users/geeyu/space/siyuan` (可被 `SIYUAN_WORKSPACE` 覆盖)。

## 引用协议 (最重要, 全部命令统一)

**所有命令的文档引用 `<doc>` 遵循同一规则, Linux 直觉, 无需学习私有协议:**

| 形式 | 示例 | 规则 |
| ------ | ------ | ------ |
| id | `20260727201107-6cawv5h` | 精确命中 |
| 完整路径 | `/工作/日志/2026/AI伴学` (或 `工作/日志/...` 无前导 /) | 必须真实存在, **不存在即报错** |
| hpath | `/日志/2026/AI伴学` (无笔记本名) | 精确匹配 |
| 通配 (显式模糊) | `/*/AI伴学`、`/工作/*/调课` | `*` 任意层级 (含零层), `?` 单字符; 多命中为正常结果 (列表命令列出全部, 单目标命令列候选报歧义) |
| 标题 | `AI伴学` (无 `/`) | 精确同名优先, **多匹配列出候选并报错** (防误操作) |

- 路径输出统一为 `/笔记本/目录…/标题` (带前导 `/`), find/grep/which -v/候选列表一致, 可直接喂回
- 块引用 `children`/`backlinks`/`insert-block --parent` 接受块 id 或文档引用 (自动定位到文档根块)
- 歧义一律列候选报错, 绝无静默选中

## 常用命令速查

### 读取 (查询类, shell 风格)

| 命令 | 作用 |
| ------ | ------ |
| `ls [引用] [-l]` | 列笔记本/文档; 引用=笔记本名\|id\|路径 (空=列笔记本, 通配 `/*/xxx`); 叶子文档显示自身 |
| `tree <doc>` | 标题树/大纲 (无标题文档输出空) |
| `cat <doc>` | 读文档 markdown 源 (最准, 不受索引滞后影响) |
| `head/tail <doc> [-n N]` | 读文档开头/末尾 N 行 (默认 10) |
| `find <关键词> [--notebook <nb>]` | 跨库搜文档标题, 输出 `doc_id<TAB>完整路径<TAB>notebook` |
| `grep <pattern> [-v] [-i] [-m 0-3]` | 内容全文检索, 输出完整路径; **管道输入时按行过滤** (`ls 工作 \| grep 调课`) |
| `which <引用> [-v]` | 定位文档 → 输出唯一 doc id; 多匹配报错并列出候选 |
| `stat <doc>` | 文档元信息 |
| `sql "<语句>" [-l N] [-H]` | 执行 SQL (默认 limit 100) |
| `children <block\|doc>` | 子块列表 (编辑前定位) |
| `backlinks <block\|doc> [--keyword]` | 反链 |

### 写入/编辑 (shell 风格)

| 命令 | 作用 |
| ------ | ------ |
| `touch --notebook <nb> --title <t> [--parent <父文档> \| --path <hpath>] [--file\|stdin]` | 建文档 (推荐入口; createDocWithMd 三步语义无中间块残留), 返回 id |
| `edit <doc> (--append\|--prepend\|--update <块id>\|--replace) <text> [--file\|stdin]` | 统一编辑入口: 追加/开头插入/改块/整篇替换, 返回目标 id |
| `mv <doc> --parent <父文档> [--notebook <nb>]` | 移动文档 (同/跨笔记本; 别名 --to), 返回文档 id |
| `cp <doc> [--parent <父文档>]` | 复制文档 (duplicate; 别名 --to), 返回新副本 id |
| `rm <doc>` | 删文档, 返回文档 id |
| `diff <docA> <docB> [diff 参数...]` | 对比两文档 markdown (统一 diff 格式; 退出码 0=同 1=异) |
| `rename <doc> <新标题>` | 重命名 (IAL title + H1 同步; **同目录重名预检**), 返回文档 id |

### 底层写入 (与 shell 风格等价, 保留兼容)

| 命令 | 作用 |
| ------ | ------ |
| `write --notebook <nb> --title <t> [--parent <父文档>\|--path <hpath>]` | 建文档 (同 touch, 推荐 touch) |
| `append <doc> [--data\|--file\|stdin]` | 追加到文档末尾 (同 edit --append) |
| `insert-block [--previous <块>\|--parent <块\|doc>] [--data]` | 插入块 |
| `update-block <block-id> [--data\|--file]` | 替换块内容 (同 edit --update) |
| `replace-doc <doc> [--data\|--file\|stdin]` | 替换整篇文档 (删旧写新, 保留标题) |
| `delete-block <block-id>` | 删除块 |
| `move <doc> --parent <父文档>\|--notebook <nb>` | 移动文档 (同 mv) |
| `remove <doc>` | 删除文档 (同 rm) |

**引用与响应统一约定**: 所有 `<doc>` 引用支持 id/标题/路径 (含通配), 每次写操作返回目标 id (可 `$(siyuan touch ...)` 直接取用); 内容传入统一支持 `--data <字符串>` / `--file <文件>` / 管道 stdin。

### 数据库 (属性视图 / AV) — 见 [references/database.md](references/database.md)

```bash
siyuan av list                          # 列出全部数据库 (名称+avID)
siyuan av keys <avID>                   # 列字段
siyuan av rows <avID> [--limit N]       # 列行数据 (走 render, TSV 可管道)
siyuan av add <avID> --values '<JSON>' [--content 标题] [--block <doc>]   # 加行 (自动反查 itemID + 写后验证)
siyuan av update <avID> --row <行ID> --values '<JSON>'    # 改行
siyuan av remove <avID> --row <行ID>    # 删行
siyuan av verify <avID>                 # 逐行打印实际值 (验证权威入口)
siyuan av export <avID>                 # 导出全量 JSON (备份)
```

关键: `--values` 传 `{字段名: 值}` 即可, 自动按字段类型嵌套 (select→数组 / date→毫秒戳); **写后自动验证**, 验证失败退出 1 并提示实际值 (底层 `item update` 的 ok 不可信)。

### 底层透传 (封装层未覆盖的完整能力)

| 命令 | 作用 |
|------|------|
| `raw <args...>` | 透传给 SiYuan-Kernel (自带 -w) |
| `raw-help <subcommand...>` | 查底层命令帮助, 例 `raw-help block insert` |

24 类底层命令 (notebook/document/block/outline/ref/sql/search/database/attr/bookmark/tag/dailynote/file/export/import/asset/history/inbox/template/repo/sync/system/workspace/serve): 见 [references/commands.md](references/commands.md)。

## 核心约定 (高频必读)

1. **创建文档优先用 `--parent`**: 思源 createDocWithMd 按 hpath 创建会重复建中间块, 封装层已用「createDocWithMd + moveDocs + 删中间块」三步自动处理 (HTTP 不可用时自动回退 CLI `document create`)。`--parent` 引用支持 id/标题/路径。
2. **判断写入成功看 `cat`, 不看 SQL**: block update/delete 后 SQL 查 `content` 可能滞后 (FlushTxQueue 异步索引, 秒级), `siyuan cat <doc>` 直接读文件是准的。没刷新 `sleep 2-3` 再查。
3. **文档名由 IAL `title` 决定, 不是 H1**: `rename` 已自动同步 (IAL title + 第一个 H1 子块); 底层 `document rename` 只改 IAL title 不改 H1, 两者会不一致。⚠ 不要对文档块本身做 `block update` (会把整篇文档内容替换掉)。
4. **notebook 参数支持中文名**: `siyuan ls 工作` 自动解析成 notebook id; 设 `SIYUAN_DEFAULT_NOTEBOOK` 后无参 `ls` 直接列该库。
5. **mv/move、cp 同/跨笔记本都适用**: `mv <doc> --parent <父文档>` 自动取父文档所在笔记本; 底层 `document move` 只能跨笔记本, 封装层自动处理。
6. **rename 有同目录重名预检**: 改出的新标题若与同父级下已有文档重名 → 报错 (防整理事故)。
7. **不知道参数时**: `siyuan raw-help <command>` 查帮助, 不要猜。
8. **退出码**: 0=成功 1=业务错误 2=用法错误 3=配置错误 124=超时; 内核调用默认 60 秒超时 (`SIYUAN_TIMEOUT` 可调)。`diff` 例外: 0=相同 1=有差异 (同系统 diff)。
9. **批量整理文档 (⚠ 高频事故区)**: ① `rm <目录>` 会**级联删除全部子文档** —— 先移出子文档再删目录, `ls` 空目录显示自身不是"有内容"; ② 同名文档很常见 (跨库/跨目录), 批量循环**用 id 不用标题** (`ls 目录 | while read -r id name; do mv "$id" ...`), 一个歧义会中断整批; ③ rename/建目录前先 `find` 预检重名; ④ 完整流程见 [references/conventions.md](references/conventions.md) §14。

> 详细约定与源码依据: 见 [references/conventions.md](references/conventions.md)。

## 典型用法

### 1. 写一篇笔记 (推荐 touch + --parent)

```bash
# 先定位目标父文档 id (用 which, 同名时用完整路径)
PARENT=$(siyuan which /工作/调课)
cat <<'EOF' | siyuan touch --notebook 工作 --title "调课逻辑梳理" --parent "$PARENT"
# 调课逻辑

## 入口
...
EOF
# 返回新文档 id
```

### 2. 搜已有笔记 + 读内容

```bash
siyuan find "调课"        # 搜文档: doc_id<TAB>完整路径<TAB>notebook
DOC=$(siyuan which 调课)   # 定位文档 → doc id (同名多匹配时报错并列出候选)
siyuan cat "$DOC"         # 读 markdown 源 (准)
siyuan tree "$DOC"        # 标题树
siyuan children "$DOC"    # 看子块结构
```

### 3. 编辑已有文档 (shell 风格)

```bash
DOC=$(siyuan which 调课)
siyuan edit "$DOC" --append "## 新章节
内容"          # 追加 (返回文档 id)
siyuan edit "$DOC" --prepend "- 开头要点"          # 开头插入
BID=$(siyuan children "$DOC" | awk -F'\t' '$2=="p"{print $1;exit}')
siyuan edit "$DOC" --update "$BID" "新段落文本"     # 改块 (返回块 id)
echo '# 整篇新内容' | siyuan edit "$DOC" --replace  # 整篇替换
siyuan rename "$DOC" "新文档名"                     # 改名 (IAL + H1 同步, 重名预检)
siyuan diff "$DOC" "$(siyuan which 另一篇)"         # 对比两文档 (rc 1=有差异)
siyuan mv "$DOC" --parent "$(siyuan which /目标目录)"   # 移动 (别名 --to)
siyuan cp "$DOC" --parent "$(siyuan which /目标目录)"   # 复制 (别名 --to)
siyuan rm "$DOC"                                    # 删除
```

### 4. 通配与批量

```bash
siyuan ls "/*/AI伴学"                      # 通配: 任意笔记本下的 AI伴学 (多命中列出全部)
siyuan ls "/工作/*/待办实现/*"             # 多层通配
siyuan ls 工作 | siyuan grep 调课          # 管道过滤
siyuan cat $(siyuan which /工作/调课)      # 定位并读
```

### 5. 录入排查记录到数据库

见 [references/database.md](references/database.md) 的「完整录入示例」。

## 工作区信息

- 内核: `/Applications/SiYuan.app/Contents/Resources/kernel/SiYuan-Kernel` (v3.8.0)
- 工作区: `/Users/geeyu/space/siyuan`
- 笔记本: 工作 / 学习 / 生活
- 思源源码 (查行为依据): `/Users/geeyu/space/code/github/siyuan`

## 故障排查

- **"找不到思源内核二进制"**: 检查 SiYuan.app 是否安装, 或设 `SIYUAN_KERNEL`
- **"工作区不存在"**: 设 `SIYUAN_WORKSPACE` 指向正确路径
- **思源没启动**: CLI 直接操作工作区文件, 不需要 App 运行; App 开着且操作了数据时, 操作后在 App 里刷新
- **命令报错 Unknown flag**: 用 `siyuan raw-help <command>` 查最新参数
- **SQL 查到旧数据**: 索引滞后, `sleep 2-3` 后重试, 或用 `cat` 验证
- **引用报"找不到"**: 路径必须完整真实存在; 模糊用通配 `/*/xxx`; 记不清路径用 `siyuan find` 搜标题
- **引用报"有 N 个匹配"**: 同名文档歧义, 用完整路径消歧 (`/工作/完整/路径/标题`) 或 `-v` 看候选
- **数据库写入不生效**: 见 [references/database.md](references/database.md); `item update` 的 ok 不可信, 用 `siyuan av verify <avID>` 验证
