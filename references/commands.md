# siyuan 命令完整参考 (shell 风格命令集 + 底层透传)

> 数据来源: `bin/siyuan` 命令注册表 + `bin/lib/*.sh` (实现) + 源码 `kernel/cli/cmd/*.go` (SiYuan-Kernel v3.8.0, 已用 `SiYuan-Kernel --help` 逐条核对)
> 分两层: ① 封装命令 `siyuan <cmd>` (shell 风格, 行式输出可管道组合); ② 底层透传 `siyuan raw <cmd>` (kernel 完整能力)
> 不确定参数时: `siyuan raw-help <cmd>` 查底层帮助, `siyuan help <cmd>` 查封装命令帮助

## 一、封装命令总表

命令注册表 (含别名) 与 `bin/siyuan` 的 `sy_register` 完全一致; 别名与主命令共享处理函数。

### 查询 (行式输出可管道, `--json` 出稳定字段)

| 命令 (别名) | 用法 | 输出 | 退出码备注 |
|------|------|------|------|
| `ls` (`notebooks`/`nb`/`list`) | `ls [笔记本] [路径] [-l] [--json]` | 无参: 笔记本 `id<TAB>name`; 有参: 文档 `id<TAB>name`; `-l` 附 子数/大小/修改时间 | 0 |
| `tree` (`outline`) | `tree <doc> [-l] [--json]` | 标题树 (按 h 层级缩进); `-l` 附块 id | 0 |
| `cat` (`read`) | `cat <doc> [--json]` | markdown 源 (走 `export md`) | 0 |
| `head` | `head <doc> [-n N] [--json]` | 开头 N 行 (默认 10, 内部 cat 截断) | 0 |
| `tail` | `tail <doc> [-n N] [--json]` | 末尾 N 行 (默认 10) | 0 |
| `find` (`search`) | `find <关键词> [--notebook <nb>] [-l N] [--json]` | `doc_id<TAB>hPath<TAB>notebook_id` (document search) | 0 |
| `grep` | `grep <pattern> [-v] [-i] [-l] [-m 0-3] [--notebook <nb>] [-s N] [--content] [--json]` | 见下方「grep 双模式」 | 无匹配退出 1 |
| `which` | `which <doc-id\|标题\|/路径> [-v] [--json]` | 唯一 doc id; `-v` 附 `id<TAB>hPath<TAB>box` | 0/1 (找不到或多匹配) |
| `stat` (`get`) | `stat <doc> [--json]` | 文本 `key: value`; `--json` 原始对象 | 0 |
| `sql` | `sql "<语句>" [-l N] [-H] [--json]` | 文本 TSV 行 (无表头, 可组合); `-H` 加表头 | 0 |
| `children` | `children <block-id> [--json]` | `id<TAB>type<TAB>content` (内容截 60 字符) | 0 |
| `backlinks` (`bl`) | `backlinks <block-id> [--keyword <kw>] [--json]` | 递归 `id<TAB>content` 行 | 0 |

**grep 双模式** (核心):
- **管道过滤模式** (stdin 非终端且未加 `--content`/`-m`): 按行过滤上游输出, 等价 `grep -E`, 支持 `-v`/`-i`。例: `siyuan ls 工作 | siyuan grep 调课`
- **内容检索模式** (stdin 是终端, 或强制 `--content`/指定 `-m`): kernel search 全文检索, 输出 `doc_id<TAB>hPath<TAB>内容` (去 `<mark>` 标签); `-l` 只列 doc_id (去重); `-m` 检索方法 0=关键词 1=query-syntax 2=sql 3=regex; `-s N` 页大小 (默认 32); 无匹配退出 1

**组合示例** (命令可管道, 统一行式输出):
```bash
siyuan ls 工作 | siyuan grep 调课          # 过滤文档列表
siyuan ls 工作 | siyuan grep -v 废弃       # 排除过滤
siyuan ls | siyuan grep 工作               # 过滤笔记本列表
siyuan find 调课 | siyuan grep 供应链       # 标题搜索结果过滤
siyuan grep 调课 -l | head -5              # 内容命中的前 5 篇文档
siyuan cat $(siyuan which /工作/调课)       # 定位并读文档 (命令替换)
siyuan sql "SELECT id,name FROM blocks WHERE type='d' LIMIT 5" | siyuan grep 调课   # SQL 结果过滤
```

### 写入/编辑 (成功输出 `ok` 或新文档 id)

| 命令 (别名) | 用法 | 输出 | 备注 |
|------|------|------|------|
| `write` (`create`) | `write --notebook <nb> --title <t> [--parent-id <pid> \| --path <hpath>] [--file <f>\|stdin]` | 新文档 id | 推荐 `--parent-id` (自动清理中间块) |
| `append` | `append <doc-id> [--data <md> \| --file <f> \| stdin]` | `ok` | 追加到文档末尾 |
| `insert-block` | `insert-block --previous <bid> \| --parent <doc-id> [--data\|--file\|stdin]` | `ok` | `--previous` 自动查 parent |
| `update-block` | `update-block <block-id> [--data\|--file\|stdin]` | `ok` | 替换块内容 |
| `replace-doc` | `replace-doc <doc-id> [--data\|--file\|stdin]` | `ok` | 删子块后重写, 保留标题 |
| `delete-block` | `delete-block <block-id>` | `ok` | 删除块 |
| `move` | `move <doc-id> --parent-id <pid>` | `ok` | 走 HTTP moveDocs, 同/跨笔记本均可 |
| `remove` (`rm`) | `remove <doc-id>` | (静默) | CLI 失败降级 HTTP removeDocByID |

### 底层与其他

| 命令 | 用法 | 备注 |
|------|------|------|
| `raw` | `raw <args...>` | 透传内核 (自带 `-w <workspace>`, 默认 table, 需 `-f json` 拿结构化) |
| `raw-help` | `raw-help <sub...>` | 底层命令帮助, 例 `raw-help block insert` |
| `help` / `-h` / `--help` | `help [命令]` | 总帮助 / 单命令帮助 |

## 二、文档引用 `<doc>` 解析规则

`which`/`cat`/`tree`/`head`/`tail`/`stat` 的 `<doc>` 参数支持三种形式 (实现: `sy_locate_docs`/`sy_resolve_doc`):
1. **doc-id**: 形如 `20260709112905-e1gm9bd`, 精确 SQL 查 `blocks` 表 (`type='d'`)
2. **/完整路径**: 以 `/` 开头, 先按 hpath 精确匹配, 无匹配回退标题搜索
3. **标题**: document search, 精确同名优先, 再宽松匹配

多匹配时报错并列出候选 (exit 1), 用 /完整路径 消歧。

## 三、计划命名 ↔ 实现命令对照

重构计划的 Linux 风格命名未全部直接实现, 功能对应如下:

| 计划名 | 实现 | 说明 |
|------|------|------|
| `ls/cat/head/tail/find/grep/tree/which/stat/sql` | 同名 ✅ | 直接实现 |
| `touch` | `write` | 建文档 (内容可空) |
| `edit` | `append` / `update-block` / `replace-doc` / `insert-block` | 按编辑粒度选 |
| `mv` | `move` | 移动文档 |
| `cp` | `raw document duplicate` | 复制文档 |
| `rm` | `remove` (别名 `rm`) | 删除文档 |
| `diff` | `cat` 两篇 + 本地 `diff`; 或 `raw repo diff --left <id> --right <id>` | 文档内容对比 / 快照对比 |
| `rename` | `raw document rename --id <id> --title <t>` | 只改 IAL title, 不改 H1 |
| `av` | `raw database ...` + `scripts/av_ops.js` | 属性视图, 见 [database.md](database.md) |

## 四、退出码契约

| 码 | 含义 | 触发例 |
|----|------|--------|
| 0 | 成功 | — |
| 1 | 业务/运行时错误 | 找不到文档/笔记本、SQL 错误、`grep` 无匹配、`which` 多匹配 |
| 2 | 用法错误 | 缺参数、未知参数、未知命令 |
| 3 | 配置错误 | 内核二进制/工作区/node 缺失 |
| 124 | 内核调用超时 | 内核 `${SIYUAN_TIMEOUT}` 秒 (默认 60) 无响应 |

错误统一写 stderr, 格式 `siyuan <命令>: <原因>` + 建议行 (`建议: ...`)。所有查询命令支持 `--json` 输出稳定字段; 设 `SIYUAN_FORMAT=json` 全局默认开启 `--json`。

## 五、环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `SIYUAN_KERNEL` | `/Applications/SiYuan.app/Contents/Resources/kernel/SiYuan-Kernel` | 内核二进制路径 |
| `SIYUAN_WORKSPACE` | `/Users/geeyu/space/siyuan` | 工作区路径 |
| `SIYUAN_FORMAT` | `text` | `json` = 默认开 `--json` |
| `SIYUAN_TIMEOUT` | `60` | 内核调用超时秒数 (0=不超时) |
| `SIYUAN_DEFAULT_NOTEBOOK` | 空 | 设置后无参 `ls` 列该笔记本文档 |
| `SIYUAN_API_HOST` / `SIYUAN_API_PORT` | `127.0.0.1` / `6806` | 内核 HTTP API (write/move 等写入兜底) |

## 六、底层透传命令参考 (raw, 24 类)

> 通过 `siyuan raw <cmd>` 调用, 建议加 `-f json` 拿结构化输出; 不确定参数时 `siyuan raw-help <cmd>`。
> 封装层 (`siyuan <cmd>`) 覆盖高频操作, 底层命令是 kernel 完整能力, 封装层未覆盖时走 raw。

封装命令支持三种输出模式 (互斥): 默认文本 (行式可管道) / `--json` (稳定字段) / `--markdown` (表格/列表/确认块, stdout 只含 markdown 可直接重定向 `.md` 或粘贴进思源)。`raw` 为原样透传, `--markdown` 无转换效果。

---

### notebook — 笔记本

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

封装: `siyuan ls` (无参列笔记本, 设 `SIYUAN_DEFAULT_NOTEBOOK` 时列该库文档)

### document — 文档

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

封装: `siyuan ls` / `siyuan write` / `siyuan cat` / `siyuan find` / `siyuan stat` / `siyuan move` / `siyuan remove`

⚠ `document move` 只能跨笔记本。同笔记本改父级用封装 `siyuan move` (走 HTTP moveDocs)。

### block — 块操作

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

### outline / ref / sql / search — 大纲、反链、查询

| 命令 | 作用 |
|------|------|
| `raw outline get --id <id>` | 取文档大纲 (标题树) |
| `raw ref backlinks --id <id> [--keyword <kw>]` | 取块反链 |
| `raw ref mentions --id <id>` | 取块提及 |
| `raw ref refresh --id <id>` | 刷新块反链 |
| `raw sql "<statement>"` | 执行 SQL (查 blocks/refs/spans 等) |
| `raw search <query>` | 全文搜索 |

封装: `siyuan tree` / `siyuan backlinks` / `siyuan sql` / `siyuan grep` (内容检索) / `siyuan find` (搜文档标题)

### database — 数据库 (属性视图)

**封装命令组 `siyuan av ...`** (适配 3.8.0 B1/B2, 推荐):

| 命令 | 作用 |
|------|------|
| `av list [--json]` | 列出全部数据库 (avID+名称+路径) |
| `av keys <avID> [--json]` | 列字段 (name/type/keyID; B1: 3.8 keys 为对象包装) |
| `av rows <avID> [--limit N] [-H] [--json]` | 列行数据 (B2: 走 render; TSV 可管道) |
| `av get <avID> --row <rowID> [--json]` | 单行详情 |
| `av add <avID> --values '<JSON>' [--content <标题>] [--block <doc-id>]` | 加行 (值自动嵌套, 自动反查 itemID, 写后验证) |
| `av update <avID> --row <rowID> --values '<JSON>'` | 改行 (写后 render 验证) |
| `av remove <avID> --row <rowID>` | 删行 (删后验证) |
| `av verify <avID> [--json]` | 逐行打印实际值 (验证权威入口) |
| `av export <avID>` | 导出全量 JSON (备份) |

完整规范 (字段类型/值结构/录入流程/排查记录库设计): 见 [database.md](database.md)。

底层 `raw database ...` (透传, 高级用): search / get (3.8 起仅结构元数据) / keys / render (行数据唯一来源) / item add|update|remove / key add|remove / unused / clean。

### attr / bookmark / tag — 属性、书签、标签

| 命令 | 作用 |
|------|------|
| `raw attr get --id <id>` | 取块属性 |
| `raw attr set --id <id> --attr name=value` | 设块属性 (可重复, 多属性) |
| `raw attr batch-get --ids id1,id2,...` | 批量取属性 |
| `raw bookmark list` | 列书签 |
| `raw bookmark labels` | 列书签标签 |
| `raw bookmark remove --label <label>` | 删书签 |
| `raw bookmark rename --old <old> --new <new>` | 重命名书签 |
| `raw tag list` | 列标签 |
| `raw tag remove --label <label>` | 删标签 |
| `raw tag rename --old <old> --new <new>` | 重命名标签 |

### dailynote — 日记

| 命令 | 作用 |
|------|------|
| `raw dailynote create --notebook <id>` | 创建今日日记 |
| `raw dailynote append --notebook <id> [--data\|--file]` | 追加到今日日记 |
| `raw dailynote prepend --notebook <id> [--data\|--file]` | 插入到今日日记开头 |

### file — 工作区文件

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

### export / import — 导入导出

| 命令 | 作用 |
|------|------|
| `raw export md --id <id> [--output <file>]` | 导出 Markdown (cat 封装用的底层, 默认输出到 stdout) |
| `raw export html --id <id>` | 导出 HTML |
| `raw export preview --id <id>` | 导出预览 HTML |
| `raw export docx --id <id> --output <file>` | 导出 Word |
| `raw export sy --id <id> [--output <file>]` | 导出 .sy.zip |
| `raw export md-zip --id <id> [--output <file>]` | 导出 Markdown zip |
| `raw export data [--output <file>]` | 导出完整工作区备份 |
| `raw import md --file <path> --notebook <id>` | 导入 Markdown 文件/目录 |
| `raw import sy --file <path> --notebook <id>` | 导入 .sy.zip |
| `raw import data --file <path>` | 导入数据备份 |

### asset — 资源文件

| 命令 | 作用 |
|------|------|
| `raw asset upload --id <id> --file <path>` | 上传文件到资源 |
| `raw asset unused` | 列未使用资源 |
| `raw asset clean` | 清理未使用资源 |
| `raw asset stat --path <path>` | 资源文件信息 |

### history — 历史记录

| 命令 | 作用 |
|------|------|
| `raw history list` | 列所有历史 |
| `raw history search <query>` | 搜索历史 |
| `raw history get --path <path>` | 取历史文件内容 |
| `raw history rollback --path <path>` | 回滚文档到历史版本 |
| `raw history clear` | 清所有历史 |

### inbox — 云端剪藏

| 命令 | 作用 |
|------|------|
| `raw inbox list [-p <page>]` | 列云端剪藏 |
| `raw inbox get --id <id>` | 取剪藏完整 markdown |
| `raw inbox convert --ids id1,id2 --notebook <id> [--path </hp>] [--remove-after]` | 转为本地文档 |

### template — 模板

| 命令 | 作用 |
|------|------|
| `raw template search [keyword]` | 搜索模板 (空关键词列全部) |
| `raw template get --path <path>` | 读模板内容 |
| `raw template create --name <name> [--data\|--file]` | 从 markdown 创建模板 |
| `raw template remove --path <path>` | 删模板 |
| `raw template render --path <path> --id <id>` | 对块渲染模板 (预览) |
| `raw template save-as --id <id> --name <name>` | 把文档存为模板 |

### repo — 数据快照

| 命令 | 作用 |
|------|------|
| `raw repo list` | 列快照 |
| `raw repo create` | 创建快照 |
| `raw repo tag --id <id> --name <name>` | 给快照打标签 |
| `raw repo untag --name <name>` | 移除标签 |
| `raw repo checkout --id <id>` | 回滚到快照 |
| `raw repo diff --left <id> --right <id>` | 对比两个快照 (diff 计划名的底层实现) |
| `raw repo search <keyword>` | 搜快照内文件 |
| `raw repo purge` | 清理旧快照 |
| `raw repo file get --id <fileID>` | 从快照取文件内容 |
| `raw repo file rollback --id <fileID>` | 从快照回滚单个文件 |
| `raw repo file open --id <fileID>` | 预览快照内文件 |
| `raw repo file export --id <fileID>` | 导出快照内文件到临时目录 |

### sync / system / workspace / serve — 同步、系统、工作区、服务

| 命令 | 作用 |
|------|------|
| `raw sync push` | 上传到云端 |
| `raw sync pull` | 从云端下载 |
| `raw sync status` | 查看同步状态 |
| `raw system current-time` | 服务器当前时间 |
| `raw workspace list` | 列已注册工作区 |
| `raw workspace info` | 当前工作区信息 |
| `raw serve` | 启动内核 HTTP 服务 |

## 七、全局参数

| 参数 | 作用 |
|------|------|
| `-w <path>` | 工作区路径 (封装层已自动带) |
| `-f json\|table` | 输出格式 (默认 table, 程序解析用 json) |
| `--dry-run` | 只打印将要执行的操作, 不实际执行 |

## 八、常见查询 SQL

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
