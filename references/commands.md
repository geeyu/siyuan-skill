# SiYuan-Kernel 完整命令参考

> 数据来源: 源码 `kernel/cli/cmd/*.go` (SiYuan-Kernel v3.8.0, 已用 `SiYuan-Kernel --help` 逐条核对)
> 通过 `siyuan raw <cmd>` 调用, 建议加 `-f json` 拿结构化输出
> 不确定参数时: `siyuan raw-help <cmd>`

## 封装命令 vs 底层命令

封装层 (`siyuan <cmd>`) 覆盖了高频操作 (文档读写、SQL、搜索等)。底层命令 (`siyuan raw <cmd>`) 是 kernel 完整能力, 封装层未覆盖时走 raw。

---

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

封装: `siyuan notebooks` (= `notebook list`)

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

封装: `siyuan write` / `siyuan read` / `siyuan search` / `siyuan get` / `siyuan move` / `siyuan remove`

⚠ `document move` 只能跨笔记本。同笔记本改父级用封装 `siyuan move` (走 HTTP moveDocs)。

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

封装: `siyuan children` / `siyuan append` / `siyuan update-block` / `siyuan insert-block` / `siyuan delete-block`

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

封装: `siyuan outline` / `siyuan backlinks` / `siyuan sql` / `siyuan search` (后者搜文档)

## database — 数据库 (属性视图)

详见 [database.md](database.md)。

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
