# siyuan 封装命令完整参考

> 这是 skill 的**主学习材料**: 全部封装命令的用途、参数、输出、示例与组合用法。
> 封装层满足不了时, 底层原始命令见 [raw.md](raw.md); 复杂功能 (数据库) 见 [database.md](database.md)。

## 通用约定 (所有命令)

- **引用 `<doc>`**: id | 路径 (完整路径 `/工作/xx` 或 hpath `/xx`, 必须真实存在) | 通配 `/*/xx` | 标题。多匹配列候选报错, 详见 SKILL.md「引用协议」。
- **输出模式** (三选一, `--json` 与 `--markdown` 互斥):
  - 默认: 人类可读文本, 行式可管道组合
  - `--json`: 稳定字段 JSON (agent 用)
  - `--markdown`: 表格/列表/确认块, stdout 只含 markdown 可直接重定向到 .md 或粘贴进思源
- **内容传入**: `--data <字符串>` / `--file <文件>` / 管道 stdin 三选一
- **写操作返回目标 id** (可 `$(siyuan touch ...)` 直接取用)
- **退出码**: 0=成功 1=业务错误 2=用法错误 3=配置错误 124=内核超时 (`diff` 例外: 0=同 1=异)

---

## 一、读取 (查询类, shell 风格)

### ls — 列笔记本/文档

```
siyuan ls [引用] [-l] [--json|--markdown]
```

- 无参: 列笔记本 (设 `SIYUAN_DEFAULT_NOTEBOOK` 后列该库根)
- `ls 工作`: 列笔记本「工作」根目录文档 (支持中文名/笔记本 id)
- `ls /工作/日志/2026/AI伴学`: 列目录下直接子文档 (路径必须真实)
- `ls "/*/AI伴学"`: 通配, `*` 任意层级含零层, `?` 单字符; 多命中列出文档本身
- `ls 调课`: 标题引用, 多匹配列候选报错
- `ls <doc-id>`: 按 id 列其子文档
- 叶子文档 (无子文档): 显示文档本身一行 (Linux `ls 文件` 语义)
- `-l`: 详情 (子文档数/大小/修改时间)

```bash
siyuan ls                        # 笔记本列表
siyuan ls 工作 | siyuan grep 调课  # 管道过滤
siyuan ls /AI伴学/待办实现 -l     # 详情模式
```

### tree — 标题树/大纲

```
siyuan tree <doc> [-l] [--json|--markdown]
```

- 标题块按层级缩进输出; `-l` 附块 id
- 无标题文档 (目录文档/空文档) 输出空, 不报错
- `--markdown`: 嵌套无序列表

### cat — 读文档 markdown 源

```
siyuan cat <doc> [--json|--markdown]
```

- 走 `export md` 直接读文件树, **最准** (不受索引滞后影响, 写入验证首选)
- 文本模式 = 纯 markdown 原样, 可管道消费; `--json` 输出 `{id, hPath, box, markdown}`

### head / tail — 读文档开头/末尾 N 行

```
siyuan head|tail <doc> [-n N] [--json|--markdown]
```

- 默认 10 行; 内部 cat 截断, 不新增内核调用

### find — 跨库搜文档标题

```
siyuan find <关键词> [--notebook <nb>] [-l N] [--json|--markdown]
```

- 输出: `doc_id<TAB>完整路径<TAB>notebook_id` (路径可直接喂回 which/ls)
- `--notebook`: 限定笔记本 (中文名/id)

### grep — 内容全文检索 / 行过滤器

```
siyuan grep <pattern> [-v] [-i] [-l] [-m 0-3] [--notebook <nb>] [-s N] [--json|--markdown]
```

- **双模式**:
  - 管道输入 (stdin 非终端): 真 grep 行过滤, 如 `siyuan ls 工作 | siyuan grep 调课`
  - 终端输入: 内容全文检索 (kernel search), `-m` 选方法: 0=关键词 1=query-syntax 2=sql 3=regex
- 内容模式输出: `doc_id<TAB>完整路径<TAB>匹配内容`; `-l` 只列 doc_id; 无匹配退出 1
- 路径与 find 格式一致, 可直接喂回

### which — 定位文档 → 唯一 doc id

```
siyuan which <引用> [-v] [--json|--markdown]
```

- 输出唯一 doc id (可组合: `cat $(siyuan which 标题)`)
- `-v`: 附完整路径/notebook; 多匹配列出候选并退出 1 (防误操作)

### stat — 文档元信息

```
siyuan stat <doc> [--json|--markdown]
```

- 文本: `key: value` (id/hPath/box/path/title/icon/updated...); `--json` 原始对象; `--markdown` 键值表

### sql — 执行 SQL

```
siyuan sql "<语句>" [-l N] [-H] [--json|--markdown]
```

- 默认 limit 100; 文本 = TSV 行 (无表头可管道, `-H` 加表头); `--markdown` 表格
- 查 blocks/refs/spans 等系统表

```bash
siyuan sql "SELECT id, content FROM blocks WHERE type='d' AND content LIKE '%调课%' LIMIT 5"
```

### children — 子块列表 (编辑前定位)

```
siyuan children <block|doc> [--json|--markdown]
```

- 输出: `block_id<TAB>type<TAB>内容` (type: d=文档 h=标题 p=段落 l=列表 i=图片...)
- 引用可为块 id 或文档引用 (文档自动定位到其根块)

### backlinks — 反链

```
siyuan backlinks <block|doc> [--keyword <kw>] [--json|--markdown]
```

---

## 二、写入/编辑 (shell 风格, 主推)

### touch — 建文档

```
siyuan touch --notebook <nb> --title <t> [--parent <父文档> | --path <hpath>] [--data <md>|--file <f>|stdin]
```

- 默认建在笔记本根; `--parent` 引用支持 id/标题/路径 (推荐, 避免中间块)
- 内容可选 (空文档 = 空文件语义)
- 内部: createDocWithMd 三步语义 (建/移/删中间块), HTTP 不可用自动回退 CLI
- 输出: 新文档 id

```bash
cat <<'EOF' | siyuan touch --notebook 工作 --title "调课逻辑" --parent "$(siyuan which /调课)"
# 调课逻辑
## 入口
...
EOF
```

### edit — 统一编辑入口

```
siyuan edit <doc> (--append|--prepend|--update <块id>|--replace) <text> [--file|stdin]
```

- `--append <text>`: 追加到文档末尾
- `--prepend <text>`: 插入到文档开头
- `--update <块id> <text>`: 改指定块 (校验块属于该文档, 防止改错块)
- `--replace <text>`: 整篇替换 (删旧写新, 保留标题)
- 文本可省略改从 `--file` / 管道 stdin (中文/引号内容推荐)
- 输出: 目标 id (append/prepend/replace = 文档 id, update = 块 id)

### mv — 移动文档

```
siyuan mv <doc> --parent <父文档> [--notebook <nb>]     (别名 --to)
```

- `--parent`: 移到该文档下, 自动取父文档所在笔记本 (同/跨库都适用)
- `--notebook`: 显式指定目标笔记本 (移到库根)
- 输出: 被移动的文档 id

### cp — 复制文档

```
siyuan cp <doc> [--parent <父文档>]     (别名 --to)
```

- duplicate, 同目录生成 "标题 (Duplicated ...)" 副本; `--parent` 复制后移到该文档下
- 输出: 新副本的文档 id

### rm — 删除文档

```
siyuan rm <doc>
```

- ⚠ 删除**目录文档会级联删除其下全部子文档** — 先移出子文档再删目录
- 输出: 被删除的文档 id

### diff — 对比两文档

```
siyuan diff <docA> <docB> [diff 参数...]
```

- 内部 export md + 系统 diff, 统一 `-u` 格式; 额外参数透传 (如 `-w` 忽略空白, `-U 5` 上下文行数)
- 退出码同 diff: 0=相同 1=有差异 2=错误

### rename — 重命名

```
siyuan rename <doc> <新标题>
```

- IAL title (文档名) + 第一个 H1 子块文本同步, 避免 title/H1 不一致
- ⚠ 同目录重名预检: 新标题与同父级下已有文档重名 → 报错
- 输出: 文档 id

---

## 三、底层写入 (id 级兼容命令, 与 shell 风格等价)

| 命令 | 作用 | 等价 |
| ------ | ------ | ------ |
| `write --notebook <nb> --title <t> [--parent <父文档>\|--path <hpath>] [--data\|--file\|stdin]` | 建文档 | touch |
| `append <doc> [--data\|--file\|stdin]` | 追加到文档末尾 | edit --append |
| `insert-block [--previous <块>\|--parent <块\|doc>] [--data\|--file\|stdin]` | 插入块 | — |
| `update-block <block-id> [--data\|--file]` | 替换块内容 | edit --update |
| `replace-doc <doc> [--data\|--file\|stdin]` | 整篇替换 (删旧写新, 保留标题) | edit --replace |
| `delete-block <block-id>` | 删除块 | — |
| `move <doc> --parent <父文档>\|--notebook <nb>` | 移动文档 | mv |
| `remove <doc>` | 删除文档 | rm |

- 引用统一支持 id/标题/路径; 每次写操作返回目标 id
- `insert-block`: `--previous` 为兄弟锚点 (自动查其父), `--parent` 为父块/文档引用

---

## 四、数据库 (AV) — `av` 命令组

见 [database.md](database.md) 完整规范。速查:

```
siyuan av list                          # 列出全部数据库 (名称+avID)
siyuan av keys <avID|库名>              # 列字段 (name/type/keyID)
siyuan av rows <avID> [--limit N] [-H]  # 列行数据 (TSV 可管道)
siyuan av get <avID> --row <行ID>       # 单行详情
siyuan av add <avID> --values '<JSON>' [--content 标题] [--block <doc>]   # 加行
siyuan av update <avID> --row <行ID> --values '<JSON>'                    # 改行
siyuan av remove <avID> --row <行ID>    # 删行
siyuan av verify <avID>                 # 逐行打印实际值 (验证权威入口)
siyuan av export <avID>                 # 导出全量 JSON (备份)
```

- `--values` 传 `{字段名: 值}` 自动按类型嵌套; 写后自动验证 (底层 item update 的 ok 不可信)
- avID 支持按库名解析; `--block` 引用支持 id/标题/路径

---

## 五、底层透传与帮助

```
siyuan raw <args...>           # 透传 SiYuan-Kernel (自带 -w; 完整 24 类命令见 raw.md)
siyuan raw-help <sub...>       # 查底层命令帮助, 例: raw-help block insert
siyuan help [命令]             # 帮助; 旧名别名: list/read/get/outline/search/notebooks 仍可用
```

---

## 六、组合用法 (管道)

```bash
siyuan ls 工作 | siyuan grep 调课                # 过滤文档列表
siyuan cat $(siyuan which /工作/调课)            # 定位并读
siyuan find 调课 | cut -f1 | head -3             # 取前 3 篇文档 id
siyuan grep 调课 -l | head -5                    # 内容命中前 5 篇
siyuan ls /AI伴学/待办实现 | while read -r id name; do ...; done   # 批量 (用 id!)
```
