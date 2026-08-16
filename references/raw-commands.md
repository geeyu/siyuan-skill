# 底层原始命令参考 (SiYuan-Kernel)

> **渐进式加载层**: 封装命令 (见 [commands.md](commands.md)) 覆盖 95% 场景, **优先用封装**。
> 仅当封装不满足时 (如属性操作/导出/模板/历史回滚) 再查这里, 或直接 `siyuan raw-help <cmd>` 实时查参数。
>
> 数据来源: 源码 `kernel/cli/cmd/*.go` (SiYuan-Kernel v3.8.0, 已逐条 `--help` 核对)
> 通过 `siyuan raw <cmd>` 调用, 建议加 `-f json` 拿结构化输出

## 命令组一览

| 组 | 能力 | 常用场景 |
|------|------|------|
| `notebook` | 笔记本增删改/开关/图标 | 建笔记本、改图标 |
| `document` | 文档增删改/移动/复制/搜索 | 底层文档操作 |
| `block` | 块级操作 (kramdown/DOM/统计/批量) | 取原始 kramdown、批量取块 |
| `outline` / `ref` / `sql` / `search` | 大纲/反链/SQL/全文搜索 | 底层查询 |
| `database` | 数据库 (AV) 底层命令 | 高级数据库操作 (封装见 database.md) |
| `attr` / `bookmark` / `tag` | 块属性/书签/标签 | 属性视图、书签管理 |
| `dailynote` | 日记 | 今日日记 |
| `file` | 工作区文件操作 | 直接读写工作区文件 |
| `export` / `import` | 导入导出 | 导出 docx/备份、导入 md |
| `asset` | 资源文件 | 上传/清理未使用资源 |
| `history` | 历史记录 | 回滚文档 |
| `inbox` | 云端剪藏 | 剪藏转本地文档 |
| `template` | 模板 | 模板管理 |
| `repo` | 数据快照 | 快照/回滚 |
| `sync` / `system` / `workspace` / `serve` | 同步/系统/工作区/HTTP 服务 | 同步、起 HTTP 服务 |

## notebook — 笔记本

| 命令 | 作用 |
|------|------|
| `raw notebook list` | 列出所有笔记本 |
| `raw notebook create --name <name>` | 创建笔记本 |
| `raw notebook remove --id <id>` | 删除笔记本 |
| `raw notebook rename --id <id> --name <name>` | 重命名笔记本 |
| `raw notebook open --id <id>` | 打开笔记本 |
| `raw notebook close --id <id>` | 关闭笔记本 |
| `raw notebook set-icon --id <id> --icon <icon>` | 设置笔记本图标 |
| `raw notebook random-icon [--id <id>]` | 随机设置图标 |


## document — 文档

| 命令 | 作用 |
|------|------|
| `raw document list --notebook <id> [--path <p>] [--hpath <hp>]` | 列出笔记本下文档 |
| `raw document create --notebook <id> --title <t> [--path <p>] [--markdown <md>]` | 创建文档 |
| `raw document get --id <id>` | 取文档信息 |
| `raw document info --id <id>` | 文档详情 |
| `raw document rename --id <id> --title <t>` | 重命名 (只改 IAL title, 不改 H1) |
| `raw document move --id <id> --notebook <id> [--path] [--hpath]` | 跨笔记本移动 |
| `raw document duplicate --id <id>` | 复制文档 |
| `raw document remove --id <id>` | 删除文档 |
| `raw document search <keyword>` | 搜索文档 |


⚠ `document move` 只能跨笔记本 (`--notebook` 必填)。封装 `siyuan mv <doc> --parent <父文档>` 自动取父文档所在笔记本, 同/跨笔记本都适用 (CLI 实现, 不依赖 HTTP)。

## block — 块操作

| 命令 | 作用 |
|------|------|
| `raw block get --id <id>` | 取块信息 |
| `raw block children --id <id>` | 取子块 |
| `raw block breadcrumb --id <id>` | 取块面包屑 |
| `raw block dom --id <id>` | 取块 DOM |
| `raw block kramdown --id <id>` | 取块 kramdown 源 (含块属性 {: id=...}) |
| `raw block stat --id <id>` | 块内容统计 |
| `raw block insert --parent <id> [--data <md>\|--file <f>] [--previous <id>]` | 插入块 |
| `raw block append --parent <id> [--data <md>\|--file <f>]` | 追加块到末尾 |
| `raw block prepend --parent <id> [--data <md>\|--file <f>]` | 插入块到开头 |
| `raw block update --id <id> [--data <md>\|--file <f>]` | 更新块内容 |
| `raw block delete --id <id>` | 删除块 |
| `raw block move --id <id> --parent <pid>` | 移动块到另一父块 |
| `raw block batch-get --ids id1,id2,...` | 批量取块信息 |
| `raw block batch-kramdown --ids id1,id2,...` | 批量取 kramdown |


⚠ `block insert` 的 `--parent` 必填, `--previous` 只是兄弟锚点。封装 `insert-block --previous <id>` 会自动查其 parent。

## outline / ref / sql — 大纲、反链、查询

| 命令 | 作用 |
|------|------|
| `raw outline get --id <id>` | 取文档大纲 (标题树) |
| `raw ref backlinks --id <id>` | 取块反链 |
| `raw ref mentions --id <id>` | 取块提及 |
| `raw ref refresh --id <id>` | 刷新块反链 |
| `raw sql "<statement>"` | 执行 SQL (查 blocks/refs/spans 等) |
| `raw search <query>` | 全文搜索 |


## database — 数据库 (属性视图)

> 封装: `siyuan av` 命令组 (推荐, 自动处理嵌套值/反查/验证, 见 commands.md)。以下为底层透传, 高级/一次性操作时用。

| 命令 | 作用 |
|------|------|
| `raw database search "<关键词>"` | 按名称搜索数据库, 拿 avID |
| `raw database get --av <avID>` | 获取数据库结构元数据 (**3.8.0 起不再含行数据**) |
| `raw database keys --av <avID>` | 列出所有字段 (列) 及 keyID (**3.8.0 为 `{id,name,keys:[]}` 包装**) |
| `raw database render --av <avID> [--query <kw>] [--view <id>] [-p 页] [-s 页大小]` | 渲染视图数据 (**行数据唯一来源**) |
| `raw database item add --av <avID> --block <blockID> --content "标题"` | 新增一行 (绑定文档块) |
| `raw database item add --av <avID> --detached --content "标题"` | 新增游离行 (不绑文档块) |
| `raw database item update --av <avID> --key <keyID> --item <itemID> --value '<json>'` | 更新单元格 (**ok 不可信, 必须 render 验证**) |
| `raw database item remove --av <avID> --ids <id1,id2>` | 删除行 |
| `raw database key add --av <avID> --name <名> --type <类型>` | 新增字段 (列) |
| `raw database key remove --av <avID> --key <keyID>` | 删除字段 |
| `raw database unused` / `clean` | 列出 / 清理未使用的数据库 |

字段类型: `block / text / number / date / select / mSelect / url / email / phone / mAsset / template / created / updated / checkbox / relation / rollup / lineNumber` (`block` 是首列主键, 建库时自带)。

### ⚠️ 3.8.0 breaking (B1/B2, 必读)

- **B1 — `database keys` 输出从数组 → 对象包装**: 新 (3.8) 返回 `{id, name, keys: [...]}`, 字段数组在 `keys` 里; 脚本需兼容判断 `Array.isArray(out) ? out : out.keys`。
- **B2 — `database get` 不再返回行数据** (`keyValues` 字段消失): 行数据改由 `database render` 提供 — `view.rows[].id` = itemID (行ID), `view.rows[].cells[].value` = 单元格 (`blockID` 关联 keyID, `block.id` = 绑定文档块 ID, detached 行带 `isDetached:true`)。**所有行数据读取/写入验证必须走 render**。

### ⚠️ 值结构对照表 (raw 手工传 `--value` 时最关键的坑)

`item update` 返回 `ok` **不代表值真写进去了**, 必须 `render` 验证。value JSON **必须按字段类型嵌套** (源码 `kernel/av/value.go` 的 ValueXxx 结构体):

| 类型 | 正确 `--value` JSON | 错误写法 (返回 ok 但不落库) |
|------|---------------------|------|
| text | `{"type":"text","text":{"content":"..."}}` | `{"type":"text","text":"..."}` |
| url / email / phone | `{"type":"url","url":{"content":"..."}}` | `{"type":"url","content":"..."}` |
| date | `{"type":"date","date":{"content":<Unix毫秒int>,"isNotEmpty":true}}` | `{"type":"date","content":"2026-07-08"}` |
| select | `{"type":"select","mSelect":[{"content":"..."}]}` | `{"type":"select","content":"..."}` (**单选内部用 mSelect 数组!**) |
| mSelect | `{"type":"mSelect","mSelect":[{"content":"A"},{"content":"B"}]}` | `{"type":"mSelect","contents":["A"]}` |
| checkbox | `{"type":"checkbox","checkbox":{"checked":true}}` | `{"type":"checkbox","checked":true}` |
| number | `{"type":"number","number":{"content":123,"isNotEmpty":true}}` | `{"type":"number","content":123}` |
| relation | `{"type":"relation","relation":{"blockIDs":["<目标行blockID>"]}}` | contents 是自动渲染的, 不需传 |
| mAsset | `{"type":"mAsset","mAsset":[{"type":"file","name":"名","content":"<url>"}]}` | type 为 file 或 image |

**静默 ok 根因**: `--value` JSON 反序列化到 `*av.Value` (字段全是嵌套对象), 顶层 `content`/`checked` 被丢弃 → 子对象 nil → 静默跳过, CLI 照常打印 ok。
日期时间戳生成: `python3 -c "import calendar;print(int(calendar.timegm((2026,7,8,0,0,0,0,0,0)))*1000)"`

### itemID 与 blockID 的区别

- **blockID**: 绑定文档块的 ID (item add 的 `--block` 值), 是首列主键指向的文档
- **itemID**: 数据库行的 ID, **每次 add 新生成** (≠ blockID); **item add 不返回 itemID**, 必须 render 反查 (`view.rows[].id`)
- **value 含双引号**: 用临时文件传递 (`--value "$(cat /tmp/v.txt)"`) 或直接用 av 命令组 (`--values @file`), shell 单引号嵌套会静默截断

## attr / bookmark / tag — 属性、书签、标签

| 命令 | 作用 |
|------|------|
| `raw attr get --id <id>` | 取块属性 |
| `raw attr set --id <id> --attr name=value` | 设块属性 |
| `raw attr batch-get --ids id1,id2,...` | 批量取属性 |
| `raw bookmark list` | 列书签 |
| `raw bookmark labels` | 列书签标签 |
| `raw bookmark remove --label <label>` | 删书签 |
| `raw bookmark rename --old <old> --new <new>` | 重命名书签 |
| `raw tag list` | 列标签 |
| `raw tag remove --label <label>` | 删标签 |
| `raw tag rename --old <old> --new <new>` | 重命名标签 |

## dailynote — 闪卡/日记

| 命令 | 作用 |
|------|------|
| `raw dailynote create --notebook <id>` | 创建今日日记 |
| `raw dailynote append --notebook <id> [--data\|--file]` | 追加到今日日记 |
| `raw dailynote prepend --notebook <id> [--data\|--file]` | 插入到今日日记开头 |

## file — 工作区文件

| 命令 | 作用 |
|------|------|
| `raw file list <path>` | 列目录 |
| `raw file read <path>` | 读文件 |
| `raw file write <path>` | 写文件 (stdin 或 --file) |
| `raw file delete <path>` | 删文件/目录 |
| `raw file rename <old> <new>` | 重命名/移动 |
| `raw file copy <src> <dst>` | 复制 |
| `raw file grep --pattern <regex> --path <path>` | 正则搜文件内容 |
| `raw file find <path>` | 递归找文件 |
| `raw file stat <path>` | 文件信息 |

## export / import — 导入导出

| 命令 | 作用 |
|------|------|
| `raw export md --id <id> [--output <file>]` | 导出 Markdown (read 封装用的底层, 默认输出到 stdout) |
| `raw export html --id <id>` | 导出 HTML |
| `raw export preview --id <id>` | 导出预览 HTML |
| `raw export docx --id <id> --output <file>` | 导出 Word |
| `raw export sy --id <id> [--output <file>]` | 导出 .sy.zip |
| `raw export md-zip --id <id> [--output <file>]` | 导出 Markdown zip |
| `raw export data [--output <file>]` | 导出完整工作区备份 |
| `raw import md --file <path> --notebook <id>` | 导入 Markdown 文件/目录 |
| `raw import sy --file <path> --notebook <id>` | 导入 .sy.zip |
| `raw import data --file <path>` | 导入数据备份 |

## asset — 资源文件

| 命令 | 作用 |
|------|------|
| `raw asset upload --id <id> --file <path>` | 上传文件到资源 |
| `raw asset unused` | 列未使用资源 |
| `raw asset clean` | 清理未使用资源 |
| `raw asset stat --path <path>` | 资源文件信息 |

## history — 历史记录

| 命令 | 作用 |
|------|------|
| `raw history list` | 列所有历史 |
| `raw history search <query>` | 搜索历史 |
| `raw history get --path <path>` | 取历史文件内容 |
| `raw history rollback --path <path>` | 回滚文档到历史版本 |
| `raw history clear` | 清所有历史 |

## inbox — 云端剪藏

| 命令 | 作用 |
|------|------|
| `raw inbox list [-p <page>]` | 列云端剪藏 |
| `raw inbox get --id <id>` | 取剪藏完整 markdown |
| `raw inbox convert --ids id1,id2 --notebook <id> [--path </hp>] [--remove-after]` | 转为本地文档 |

## template — 模板

| 命令 | 作用 |
|------|------|
| `raw template search [keyword]` | 搜索模板 (空关键词列全部) |
| `raw template get --path <path>` | 读模板内容 |
| `raw template create --name <name> [--data\|--file]` | 从 markdown 创建模板 |
| `raw template remove --path <path>` | 删模板 |
| `raw template render --path <path> --id <id>` | 对块渲染模板 (预览) |
| `raw template save-as --id <id> --name <name>` | 把文档存为模板 |

## repo — 数据快照

| 命令 | 作用 |
|------|------|
| `raw repo list` | 列快照 |
| `raw repo create` | 创建快照 |
| `raw repo tag --id <id> --name <name>` | 给快照打标签 |
| `raw repo untag --name <name>` | 移除标签 |
| `raw repo checkout --id <id>` | 回滚到快照 |
| `raw repo diff --left <id> --right <id>` | 对比两个快照 |
| `raw repo search <keyword>` | 搜快照内文件 |
| `raw repo purge` | 清理旧快照 |
| `raw repo file get --id <fileID>` | 从快照取文件内容 |
| `raw repo file rollback --id <fileID>` | 从快照回滚单个文件 |
| `raw repo file open --id <fileID>` | 预览快照内文件 |
| `raw repo file export --id <fileID>` | 导出快照内文件到临时目录 |

## sync / system / workspace — 同步、系统、工作区

| 命令 | 作用 |
|------|------|
| `raw sync push` | 上传到云端 |
| `raw sync pull` | 从云端下载 |
| `raw sync status` | 查看同步状态 |
| `raw system current-time` | 服务器当前时间 |
| `raw workspace list` | 列已注册工作区 |
| `raw workspace info` | 当前工作区信息 |
| `raw serve` | 启动内核 HTTP 服务 |

## 全局参数

| 参数 | 作用 |
|------|------|
| `-w <path>` | 工作区路径 (封装层已自动带) |
| `-f json\|table` | 输出格式 (默认 table, 程序解析用 json) |
| `--dry-run` | 只打印将要执行的操作, 不实际执行 |

## 常见查询 SQL

```sql
-- 按名称查文档 (type='d')
SELECT id, content, hpath FROM blocks WHERE type='d' AND content LIKE '%关键词%' LIMIT 10;

-- 查某文档下所有子块 (root_id 是文档块 id)
SELECT id, type, content FROM blocks WHERE root_id='<doc-id>' AND type!='d';

-- 查数据库(AV)块
SELECT id, content FROM blocks WHERE type='d' AND content LIKE '%库%';

-- 查某文档的标题块 (用于改名时定位 H1)
SELECT id FROM blocks WHERE root_id='<doc-id>' AND type='h' AND subtype='h1' LIMIT 1;

-- 查反链
SELECT * FROM refs WHERE def_block_id='<block-id>';
```
