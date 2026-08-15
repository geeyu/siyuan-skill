# 思源操作约定与源码依据

> 详细版约定, 含源码级根因。日常操作看 SKILL.md 顶部精简版即可, 遇到异常或想深入理解行为时查本文件。
> 版本: SiYuan-Kernel 3.8.0; 源码: `/Users/geeyu/space/code/github/siyuan`
> 命令名以新 shell 风格封装为准 (`ls/cat/tree/which/stat/...`; 旧名 `list/read/get/outline/search/notebooks` 为别名)。

## 1. notebook 参数支持中文名

`siyuan ls 工作` 会自动解析成 notebook id。
源码: 封装层 `bin/lib/framework.sh` 的 `sy_resolve_notebook()`, 先匹配 id 格式正则 `^[0-9]{14}-[a-z0-9]{6,8}$`, 不匹配则按名查 `notebook list`。

## 2. 创建文档优先用 --parent-id

思源 `createDocWithMd` 按 hpath 创建会重复建同名中间块 (API 固有问题)。
封装层 `write` 已用「createDocWithMd + moveDocs + 删中间块」三步自动处理:
1. `createDocWithMd` 按完整 hpath 创建 (会产生中间块)
2. `moveDocs` 把新文档移到目标父块下
3. 删除产生的空中间块 (`removeDocByID`)

调用方只需传 `--parent-id`, 不会有副作用。
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
- `siyuan cat <doc-id>` 走 `export md` 直接读文件树, 是准的

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
封装层 `siyuan move <doc-id> --parent-id <pid>` 自动走 HTTP API `moveDocs`:
- 查文档 from_path 和目标 to_path (父文档 .sy 路径)
- 调 `/api/filetree/moveDocs`

同/跨笔记本都适用。
源码: 封装层 `cmd_move`; 思源侧 `documentMoveCmd` 要求 `--notebook`。

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

`siyuan replace-doc <doc-id>` 会先删文档下所有子块 (跳过文档块本身 type='d'), 再 append 新内容。
文档名/标题块保留, 不会被覆盖。
源码: 封装层 `cmd_replace_doc`, 用 SQL 查 `root_id='$id' AND type != 'd'` 拿子块逐个删。

## 10. 数据库 item update 返回 ok ≠ 写入成功

`database item update` 对错误 value 结构**静默返回 ok** 但不落库 (CLI bug)。
根因: `--value` 的 JSON 被反序列化到 `av.Value` 结构体, 其字段是嵌套对象 (`text/url/date/mSelect/checkbox/...`), 用顶层 `content`/`checked` 会被丢弃。
**必须用 `database render` 验证行数据是否有值** (3.8.0 起 `database get` 无行数据, 见 database.md B2)。
详见 [database.md](database.md) 的「值结构对照表」。

## 11. 数据库 item add 不返回 itemID

add 成功只返回 `ok`/`item added`, itemID (行 ID) 每次新生成且**不等于传入的 blockID**。
反查 (3.8.0): `database render` 的 `view.rows[].cells[]` 中主键 block 列的 `value.blockID` 即 itemID (不是 `value.block.id`, 后者是绑定的文档块)。
CLI 和 MCP 行为一致。
源码: `kernel/model/attribute_view.go` AddAttributeViewBlock 第 3685 行 `srcItemID = ast.NewNodeID()`。

## 12. 字段不能重命名, 只能删后重建

思源 CLI 没有 `key rename` 命令, 字段创建后名称固定。要改名只能 `key remove` 删除后 `key add` 新建, **会丢失该字段所有行的值**。
重建排查记录库字段时的正确流程: 先 `raw database render --av <avID>` 导出全量数据备份 → 删旧字段 → 建新字段 → 用 av_ops.js 按新字段名回填。

## 13. value 含双引号时用临时文件传递 (shell 脚本)

`--value '<json>'` 单引号包裹时, JSON 内双引号与 shell 引号嵌套冲突, 导致 value 被截断**静默不落库** (CLI 仍返回 ok)。
根因: shell 对 `'..."..."...'` 的处理把 JSON 破坏, 内核反序列化时子对象为 nil 跳过。
可靠做法: `echo -n "$VAL" > /tmp/v.txt` 再 `--value "$(cat /tmp/v.txt)"`, 或直接用 `scripts/av_ops.js` (JS 里无 shell 引号问题)。
这是重建排查记录库踩到的核心坑, 已封装进 av_ops.js。
