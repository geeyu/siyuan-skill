# 思源操作约定与源码依据

> 详细版约定, 含源码级根因。日常操作看 SKILL.md 顶部精简版即可, 遇到异常或想深入理解行为时查本文件。
> 版本: SiYuan-Kernel 3.8.0; 源码: `/Users/geeyu/space/code/github/siyuan`
> 命令名以新 shell 风格封装为准 (`ls/cat/tree/which/stat/...`; 旧名 `list/read/get/outline/search/notebooks` 为别名)。

## 1. notebook 参数支持中文名

`siyuan ls 工作` 会自动解析成 notebook id。
源码: 封装层 `bin/lib/framework.sh` 的 `sy_resolve_notebook()`, 先匹配 id 格式正则 `^[0-9]{14}-[a-z0-9]{6,8}$`, 不匹配则按名查 `notebook list`。

## 2. 创建文档优先用 --parent

思源 `createDocWithMd` 按 hpath 创建会重复建同名中间块 (API 固有问题)。
封装层 `touch`/`write` 已用「createDocWithMd + moveDocs + 删中间块」三步自动处理:
1. `createDocWithMd` 按完整 hpath 创建 (会产生中间块)
2. `moveDocs` 把新文档移到目标父块下
3. 删除产生的空中间块 (`removeDocByID`)

调用方只需传 `--parent` (id/标题/路径, 旧名 `--parent-id` 兼容), 不会有副作用。
源码: 封装层 `bin/lib/cmd-write.sh` 的 `cmd_write`, 思源侧 `kernel/api/filetree.go` createDocWithMd。

## 3. markdown 内容传入方式

`write`/`append`/`insert-block`/`update-block`/`replace-doc` 统一支持三种:
- `--data <字符串>`
- `--file <文件路径>`
- 管道 stdin (`echo '...' | siyuan write ...`)

封装层统一用 `cmd_*` 里的 `data=$(cat)` 兜底 stdin。

## 4. 判断写入成功看 cat, 不看 SQL

思源 block update/delete 后, SQL 查 `content` 字段可能滞后 (事务队列 `FlushTxQueue` 异步索引)。
- SQL (`siyuan sql`) 查的是数据库, content 由事务队列异步更新, 秒级滞后
- `siyuan cat <doc>` 走 `export md` 直接读文件树, 是准的

索引滞后通常秒级, 实在没刷新 `sleep 2-3` 后再查, 不要反复重试。
源码: `kernel/model/file.go` RenameDoc 调 `FlushTxQueue()`; `kernel/sql/block.go` `updateRootContent` 确认 content 由事务更新。

## 5. 文档名由 IAL title 决定, 不是 H1

`raw document rename` 只改 IAL `title` 属性, 不改文档内 H1 文本。
源码: `kernel/model/file.go` 的 `RenameDoc`, 仅 `tree.Root.SetIALAttr("title", title)`, 不动 H1 块。

默认建文档时 IAL title 与首个 H1 一致, 所以像「跟随 H1」, 但 rename 后两者会不一致。
要 H1 也同步改名, 需额外:
```bash
# 先定位 H1 块 id (sql 文本输出为 TSV 行, 单列查询取首行即可)
H1=$(siyuan sql "SELECT id FROM blocks WHERE root_id='$DOC' AND type='h' AND subtype='h1' LIMIT 1" | head -1)
siyuan update-block "$H1" --data "# 新标题"
```

## 6. 移动文档用 move 封装命令

底层 `document move` 只能跨笔记本 (`--notebook` 必填), 同笔记本改父级会失败。
封装层 `siyuan move <doc> --parent <父文档>` (同 `mv`, 引用支持 id/标题/路径) 自动处理:
- 解析目标父文档 → 取其所在笔记本为 toNotebook、.sy 路径为 toPath
- CLI `document move --id <doc> --notebook <toNotebook> --path <toPath>` (不依赖 HTTP serve)

同/跨笔记本都适用。
源码: 封装层 `cmd_move`/`cmd_mv`; 思源侧 `documentMoveCmd` 要求 `--notebook`。

## 7. 孤儿块

物理删了文件但索引库还有记录时, `remove` 可能报 tree not found。
封装层 `cmd_remove` 先试 CLI `document remove`, 失败则降级用 HTTP `removeDocByID`。
实在清不掉, 重启内核可清索引。

## 8. insert-block 的 previous 与 parent

底层 `block insert` 要求 `--parent` 必填, `--previous` 只是兄弟锚点 (插入在该块之后)。
封装 `siyuan insert-block --previous <id>` 会自动查其 parent:
```bash
parent=$(siyuan sql "SELECT parent_id FROM blocks WHERE id='$prev'" | head -1)
```
找不到 parent 时报错提示显式传 `--parent`。
源码: 封装层 `cmd_insert_block`; 思源侧 `blockInsertCmd`。

## 9. replace-doc 保留标题

`siyuan replace-doc <doc>` 会先删文档下所有子块 (跳过文档块本身 type='d'), 再 append 新内容。引用支持 id/标题/路径。
文档名/标题块保留, 不会被覆盖。
源码: 封装层 `cmd_replace_doc`, 用 SQL 查 `root_id='$id' AND type != 'd'` 拿子块逐个删。

## 10. 数据库 item update 返回 ok ≠ 写入成功

`database item update` 对错误 value 结构**静默返回 ok** 但不落库 (CLI bug)。
根因: `--value` 的 JSON 被反序列化到 `av.Value` 结构体, 其字段是嵌套对象 (`text/url/date/mSelect/checkbox/...`), 用顶层 `content`/`checked` 会被丢弃。
**必须用 `database render` 验证行数据是否有值** (3.8.0 起 `database get` 无行数据, 见 raw-commands.md B2)。
详见 [commands.md](commands.md) 的「值结构对照表」。

## 11. 数据库 item add 不返回 itemID

add 成功只返回 `ok`/`item added`, itemID (行 ID) 每次新生成且**不等于传入的 blockID**。
3.8.0 起 (B2) 需用 `database render` 反查 `view.rows[].id` (block 单元格的 `value.block.id` 是绑定的文档块 ID); `database get` 已不再返回行数据。
**推荐直接用 `siyuan db add`** (自动反查 + 写后验证), 底层 raw 行为见上。
CLI 和 MCP 行为一致。
源码: `kernel/model/attribute_view.go` AddAttributeViewBlock 第 3685 行 `srcItemID = ast.NewNodeID()`。

## 12. 字段不能重命名, 只能删后重建

思源 CLI 没有 `key rename` 命令, 字段创建后名称固定。要改名只能 `key remove` 删除后 `key add` 新建, **会丢失该字段所有行的值**。
重建排查记录库字段时的正确流程: 先 `siyuan db export <avID>` 导出全量数据备份 → 删旧字段 → 建新字段 → 用 `siyuan db add/update` 按新字段名回填。

## 13. value 含双引号时用临时文件传递 (shell 脚本)

`--value '<json>'` 单引号包裹时, JSON 内双引号与 shell 引号嵌套冲突, 导致 value 被截断**静默不落库** (CLI 仍返回 ok)。
根因: shell 对 `'..."..."...'` 的处理把 JSON 破坏, 内核反序列化时子对象为 nil 跳过。
可靠做法: `echo -n "$VAL" > /tmp/v.txt` 再 `--value "$(cat /tmp/v.txt)"`, 或直接用 `siyuan db add/update --values @file/stdin` (自动处理引号与嵌套)。
这是本次重建排查记录库踩到的核心坑, 已封装进 db 命令组 (别名 av)。

## 14. 批量整理文档 (移动/重命名/建目录) 的踩坑规范

真实案例: 整理 AI伴学 36 篇文档 (8/16), 踩到以下坑, 沉淀为规范:

### 14.1 ⚠ rm 目录会级联删除全部子文档

`rm <目录文档>` 删除目录时, **其下所有子文档被一并删除** (思源级联语义)。
**规范**: 删目录前必须先移出全部子文档 → 确认 `ls <目录>` 无子项 → 再 `rm <目录>`。
`ls <空目录>` 会显示目录自身一行 (叶子文档语义), 不要误读为有内容。

### 14.2 ⚠ 标题引用有歧义时整批操作中断

同名文档跨笔记本/目录普遍存在 (如「架构设计」「调课」都有 2 个)。
批量循环里用**标题**引用, 一个歧义就报错中断整批 (`while read` 循环里命令失败后变量仍推进, 造成"静默少处理几篇"的假象)。
**规范**: 批量循环一律用 **id 循环**: `ls <目录> | while IFS=$'\t' read -r id name; do siyuan mv "$id" --parent <目标>; done`
单条操作遇歧义, 改用完整路径: `siyuan mv /工作/日志/2026/AI伴学/架构设计 ...`

### 14.3 ⚠ rename 前先查目标名是否已存在

新建目录/重命名前, 先 `siyuan find <新名字>` 确认无重名 (含其他笔记本)。
真实事故: 先 `touch 03-架构设计` 建目录, 又把「关键流程」`rename 架构设计` → 同目录下两个「架构设计」并存。
**规范**: 建目录与 rename 二选一, 不要两个都做; 重命名用 `find` 预检。

### 14.4 整理推荐顺序

1. `ls <根>/**` 通配列出全部文档, 盘点数量与归属
2. 先建目标目录 (`touch --parent`), **一次建好全部** (减少中间态)
3. 批量移动用 id 循环 (见 14.2), 每批后 `ls` 核对数量
4. rename 在移动前做 (rename 不改变父级, 移动后路径变化会引入歧义)
5. 删空目录放最后 (见 14.1)
6. 收尾: 通配 `ls` 总数 = 文档数 + 目录数, 与盘点对账; 抽查 2-3 篇 `cat` 确认内容无损
