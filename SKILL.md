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

## 入口

```bash
~/.pi/skills/siyuan/bin/siyuan <command> [args]
```

shell 风格命令集 (类似 Linux 命令操作思源笔记): 默认人类可读文本 (行式可管道组合), `--json` 输出稳定字段 (agent 用), 写入操作返回 doc/block id。工作区 `/Users/geeyu/space/siyuan` (可被 `SIYUAN_WORKSPACE` 覆盖)。

## 常用命令速查

### 读取 (查询类, shell 风格)
| 命令 | 作用 |
|------|------|
| `ls [笔记本] [路径] [-l]` | 列笔记本/文档 (笔记本可传中文名, 路径支持 /hpath) |
| `tree <doc>` | 标题树/大纲 |
| `cat <doc>` | 读文档 markdown 源 (最准, 不受索引滞后影响) |
| `head/tail <doc> [-n N]` | 读文档开头/末尾 N 行 (默认 10) |
| `find <关键词> [--notebook <nb>]` | 跨库搜文档标题, 输出 `doc_id<TAB>hpath<TAB>notebook` |
| `grep <pattern> [-v] [-i] [-m 0-3]` | 内容全文检索; **管道输入时按行过滤** (`ls 工作 \| grep 调课`) |
| `which <doc-id\|标题\|/路径> [-v]` | 定位文档 → 输出唯一 doc id (多匹配报错并列出候选) |
| `stat <doc>` | 文档元信息 |
| `sql "<statement>" [-l N]` | 执行 SQL (默认 limit 100) |
| `children <block-id>` | 列子块 (编辑前定位) |
| `backlinks <block-id> [--keyword]` | 查反链 |

> `<doc>` 可以是 doc-id / 标题 / /完整路径; 组合示例: `siyuan cat $(siyuan which /工作/调课)`、`siyuan ls 工作 | siyuan grep 调课`。旧命令名 list/read/get/outline/search/notebooks 保留为别名。

### 写入/编辑
| 命令 | 作用 |
|------|------|
| `touch --notebook <nb> --title <t> [--parent <pid> \| --path <hpath>] [--file\|stdin]` | 建文档 (默认笔记本根; createDocWithMd 三步语义无中间块残留), 返回 id |
| `edit <doc> (--append\|--prepend\|--update <块id>\|--replace) <text> [--file\|stdin]` | 统一编辑入口: 追加/开头插入/改块/整篇替换, 返回目标 id |
| `mv <doc> --to <父id> [--notebook <nb>]` | 移动文档 (同/跨笔记本), 返回文档 id |
| `cp <doc> [--to <父id>]` | 复制文档 (duplicate), 返回新副本 id |
| `rm <doc>` | 删文档 (接受 id/标题/路径引用), 返回文档 id |
| `diff <docA> <docB> [diff 参数...]` | 对比两文档 markdown (统一 diff 格式; 退出码 0=同 1=异) |
| `rename <doc> <新标题>` | 重命名 (IAL title + H1 同步, 避免不一致), 返回文档 id |
| `write --notebook <nb> --title <t> [--parent-id <pid> \| --path <hpath>] [--file\|stdin]` | 建文档 (推荐 --parent-id), 返回 id |
| `append <doc-id> [--data\|--file\|stdin]` | 追加到文档末尾 |
| `insert-block --previous <bid>\|--parent <doc-id> [--data]` | 插入块 |
| `update-block <block-id> [--data\|--file]` | 替换块内容 |
| `replace-doc <doc-id> [--data\|--file\|stdin]` | 替换整篇文档 (删旧写新, 保留标题) |
| `delete-block <block-id>` | 删除块 |
| `move <doc-id> --parent-id <pid>` | 移动文档到另一父文档下 |
| `remove <doc-id>` | 删文档 (id 级) |

内容传入统一支持 `--data <字符串>` / `--file <文件>` / 管道 stdin; 每次写操作返回目标 id (可 `$(siyuan touch ...)` 直接取用)。

### 底层透传 (封装层未覆盖的完整能力)
| 命令 | 作用 |
|------|------|
| `raw <args...>` | 透传给 SiYuan-Kernel (自带 -w) |
| `raw-help <subcommand...>` | 查底层命令帮助, 例 `raw-help block insert` |

**完整的底层命令参考** (24 类命令: notebook/document/block/outline/ref/sql/search/database/attr/bookmark/tag/dailynote/file/export/import/asset/history/inbox/template/repo/sync/system/workspace/serve): 见 [references/commands.md](references/commands.md)。

常用底层命令速查:
```bash
siyuan raw document rename --id <id> --title <t>   # 重命名 (只改 IAL title, 不改 H1)
siyuan raw document duplicate --id <id>             # 复制文档
siyuan raw block prepend --parent <id> [--data]     # 文档开头插入块
siyuan raw block move --id <id> --parent <pid>      # 移动块
siyuan raw block kramdown --id <id>                 # 原始 kramdown (含块属性 {: id=...})
siyuan raw export docx --id <id> --output <file>    # 导出 Word
```

## 核心约定 (高频必读)

1. **创建文档优先用 `--parent-id`/`--parent`**: 思源 createDocWithMd 按 hpath 创建会重复建中间块, 封装层已用「createDocWithMd + moveDocs + 删中间块」三步自动处理 (HTTP 不可用时自动回退 CLI `document create`, 无中间块问题), 直接用即可。
2. **判断写入成功看 `read`, 不看 SQL**: block update/delete 后 SQL 查 `content` 可能滞后 (FlushTxQueue 异步索引, 秒级), `siyuan cat <doc-id>` 直接读文件是准的。没刷新 `sleep 2-3` 再查。
3. **文档名由 IAL `title` 决定, 不是 H1**: `rename` 命令已自动同步 (IAL title + 第一个 H1 子块文本); 底层 `document rename` 只改 IAL title 不改 H1 文本, 两者会不一致。⚠ 不要对文档块本身做 `block update` (会把整篇文档内容替换掉)。
4. **notebook 参数支持中文名**: `siyuan ls 工作` 自动解析成 notebook id; 设 `SIYUAN_DEFAULT_NOTEBOOK` 后无参 `ls` 直接列该库。
5. **mv/cp 同/跨笔记本都适用**: `mv <doc> --to <父id>` 自动取父文档所在笔记本, 跨库无需额外参数; 底层 `document move` 只能跨笔记本, 封装层自动处理。
6. **不知道参数时**: `siyuan raw-help <command>` 查帮助, 不要猜。
7. **退出码**: 0=成功 1=业务错误 2=用法错误 3=配置错误 124=超时; 内核调用默认 60 秒超时 (`SIYUAN_TIMEOUT` 可调)。`diff` 例外: 0=相同 1=有差异 (同系统 diff)。

> 详细约定与源码依据: 见 [references/conventions.md](references/conventions.md)。

## 数据库 (属性视图 / AV)

需要录入结构化数据 (排查记录、台账、问题清单等) 且需多维统计时, 使用数据库功能。
**这是复杂操作, 单独有完整文档**: [references/database.md](references/database.md)。

关键提醒 (避免踩坑):
- 数据库必须先在思源 App 里创建, CLI 只能操作已存在的库
- `database item update` 返回 `ok` **不代表写入成功** (CLI bug, 错误 value 结构静默失败), 必须 `database get` 验证
- value 的 JSON 必须按字段类型嵌套 (如 select 用 `mSelect` 数组, date 用 Unix 毫秒时间戳)
- `item add` 不返回 itemID, 需 get 反查 `values[].blockID`
- **value 含双引号时用临时文件传递**, 或直接用 `scripts/av_ops.js` 工具库 (推荐)

**工具库 `scripts/av_ops.js`** (JS, 推荐): 封装所有 AV 操作, 自动处理引号陷阱和嵌套结构:
```bash
node scripts/av_ops.js search "排查记录"   # 查 avID
node scripts/av_ops.js verify <avID>         # 验证所有行字段实际值
node scripts/av_ops.js export <avID>         # 导出 JSON (备份)
```
便捷填值方法自动构造正确结构: `setCellSelect` (自动用 mSelect)、`setCellDate` (自动转毫秒)、`setCellText` (自动处理引号)。

**排查记录库** (已建): avID `20260709112905-e1gm9bd`, 字段设计见 database.md。

## 典型用法

### 1. 写一篇笔记 (推荐 --parent-id)
```bash
# 先定位目标父文档 id (用 which, 同名时用完整路径)
PARENT=$(siyuan which /工作/调课)
cat <<'EOF' | siyuan write --notebook 工作 --title "调课逻辑梳理" --parent-id "$PARENT"
# 调课逻辑

## 入口
...
EOF
# 返回新文档 id
```

### 2. 搜已有笔记 + 读内容
```bash
siyuan find "调课"        # 搜文档: doc_id<TAB>hpath<TAB>notebook
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
siyuan rename "$DOC" "新文档名"                     # 改名 (IAL + H1 同步)
siyuan diff "$DOC" "$(siyuan which 另一篇)"         # 对比两文档 (rc 1=有差异)
siyuan mv "$DOC" --to "$(siyuan which /目标目录)"   # 移动
siyuan cp "$DOC" --to "$(siyuan which /目标目录)"   # 复制
siyuan rm "$DOC"                                    # 删除
```

### 4. 定位目录 + 移动文档
```bash
# 同名平级目录 (如 调课/调场) 用完整路径消歧
NEW_PARENT=$(siyuan which /调场)
siyuan move <doc-id> --parent-id "$NEW_PARENT"
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
- **SQL 查到旧数据**: 索引滞后, `sleep 2-3` 后重试, 或用 `read` 验证
- **数据库写入不生效**: 见 [references/database.md](references/database.md), `item update` 的 ok 不可信, 用 `node scripts/av_ops.js verify <avID>` 验证; value 含双引号用临时文件或 av_ops.js
