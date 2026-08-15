# 思源数据库 (属性视图 / Attribute View) 完整规范

> 思源的「数据库」官方叫**属性视图 (Attribute View, AV)**, 是嵌在文档里的表格型结构化数据。
<<<<<<< HEAD
> **首选 `siyuan av` 命令组** (自动处理嵌套值/引号/反查/写入验证), 底层 `siyuan raw database ...` 透传备用。
> 源码: `kernel/av/value.go` (结构体), `kernel/model/attribute_view.go` (逻辑)
> 兼容性: 适配 SiYuan-Kernel **3.8.0** — B1: `database keys` 输出为 `{id,name,keys:[]}` 对象; B2: 行数据不再由 `database get` 提供, 全部走 `database render` (详见下方「3.8.0 结构变更」)
=======
> **av 命令组** = 底层透传 `siyuan raw database ...` + 工具库 `scripts/av_ops.js` (推荐)。
> 源码: `kernel/av/value.go` (结构体), `kernel/model/attribute_view.go` (逻辑); 版本 SiYuan-Kernel **3.8.0** (含 B1/B2 breaking, 见下)
>>>>>>> gittree-wf-siyuan-w1-4

## 何时使用

- 用户要把排查记录 / 问题清单 / 资源台账等**结构化数据**录入思源, 且需要按多个维度筛选统计时
- 用户提到「数据库」「属性视图」「排查记录库」「字段」「表格」「AV」等

## 前提与定位

1. **数据库必须先在思源 App 里创建** (插入块 → 数据库视图)。CLI 只能操作已存在的数据库, 不能凭空建 AV 块。
2. **拿到 avID**: 数据库是嵌在文档里的块, avID 是该块的 ID (≠ 文档 ID)。定位:
   ```bash
   # 按名称搜 (推荐, 直接返回 avID)
   siyuan raw database search "排查记录" -f json
   # 或用 SQL
   siyuan sql "SELECT id, content FROM blocks WHERE type='d' AND content LIKE '%库%'"
   ```
   `database search` 返回里 `avID` 字段就是要用的 ID。

## ⚠️ 3.8.0 breaking 变更 (B1/B2, 必读)

> 来源: `COMPAT-REPORT-3.8.0.md` (对实际安装内核 3.8.0 验证)。3.7 → 3.8 有两处**输出结构**变更, 影响所有依赖旧结构的流程:

### B1. `database keys` 输出从数组 → 对象包装

- 旧 (3.7): `[...]` 字段数组
- 新 (3.8): `{"id": "<avID>", "name": "<库名>", "keys": [...]}` (**字段数组在 `keys` 里**)
- 用法: 解析后取 `data.keys`; 脚本需兼容判断 `Array.isArray(out) ? out : out.keys`

### B2. `database get` 不再返回行数据 (keyValues 字段消失)

- 旧 (3.7): `database get` 返回含 `keyValues` (每字段的 values 数组, 含行数据)
- 新 (3.8): `database get` 仅返回 `{id, name, keys, views}` (**结构元数据, 无行数据**)
- 行数据改由 **`database render`** 提供: `view.rows[].id` = itemID (行 ID); `view.rows[].cells[].value` = `{keyID, blockID, type, ...}` (单元格值, blockID 为绑定文档块 ID)
- 影响: 「item add 后反查 itemID」「写入后用 get 验证」两处流程全部改为 `render` (见下)

## 命令清单 (av 命令组)

### `siyuan av` 命令组 (推荐, 适配 3.8.0)

| 命令 | 作用 |
|------|------|
| `av list [--json]` | 列出全部数据库 (avID + 名称 + 路径) |
| `av keys <avID> [--json]` | 列字段 (name/type/keyID; 已适配 B1 对象包装) |
| `av rows <avID> [--limit N] [-H] [--json]` | 列行数据 (走 render, 适配 B2; 文本=TSV 可管道) |
| `av get <avID> --row <rowID> [--json]` | 单行详情 |
| `av add <avID> --values '<JSON>' [--content <标题>] [--block <doc-id>]` | 加行 (值自动按类型嵌套, 自动反查 itemID) |
| `av update <avID> --row <rowID> --values '<JSON>'` | 改行 (写后 render 自动验证, 失败退出 1) |
| `av remove <avID> --row <rowID>` | 删行 (删后验证行已消失) |
| `av verify <avID> [--json]` | 逐行打印所有字段实际值 (验证权威入口) |
| `av export <avID>` | 导出全量 JSON (备份/迁移) |

`<avID|库名>` 支持传 avID 或库名 (模糊搜首个匹配)。`av add/update` 的 `--values` 为 `{字段名: 值}` JSON, **值传简单形式即可** (见「av 命令的值规则」), 含引号用 `--values @file` 或管道 stdin。

### 底层 `raw database ...` (透传, 高级/一次性操作用)

| 命令 | 作用 |
|------|------|
| `raw database search "<关键词>"` | 按名称搜索数据库, 拿 avID |
<<<<<<< HEAD
| `raw database get --av <avID>` | 获取数据库结构元数据 (**3.8.0 起不再含行数据**, 行数据用 render) |
| `raw database keys --av <avID>` | 列出所有字段 (列) 及 keyID (3.8.0 为 `{id,name,keys:[]}`) |
| `raw database render --av <avID> [--query <kw>] [--view <id>] [-p 页] [-s 页大小]` | 渲染视图数据 (行数据唯一来源) |
=======
| `raw database get --av <avID>` | 获取数据库**结构元数据** `{id,name,keys,views}` (3.8.0 起无行数据, 见 B2) |
| `raw database keys --av <avID>` | 列出所有字段 (列) 及 keyID (**3.8.0 返回 `{id,name,keys:[]}` 包装**, 见 B1) |
| `raw database render --av <avID> [--query <kw>] [--view <id>]` | **取行数据的唯一入口** (3.8.0): `view.rows[].id`=itemID, `view.rows[].cells[].value`=单元格 |
>>>>>>> gittree-wf-siyuan-w1-4
| `raw database item add --av <avID> --block <blockID> --content "标题"` | 新增一行 (绑定文档块) |
| `raw database item add --av <avID> --detached --content "标题"` | 新增游离行 (不绑文档块) |
| `raw database item update --av <avID> --key <keyID> --item <itemID> --value '<json>'` | 更新某个单元格 (**ok 不可信, 必须 render 验证**) |
| `raw database item remove --av <avID> --ids <id1,id2>` | 删除行 |
| `raw database key add --av <avID> --name <名> --type <类型>` | 新增字段 (列) |
| `raw database key remove --av <avID> --key <keyID>` | 删除字段 |
| `raw database unused` / `clean` | 列出 / 清理未使用的数据库 |

所有 `raw` 命令建议加 `-f json` 拿结构化输出便于解析。

## 字段类型 (--type)

`block / text / number / date / select / mSelect / url / email / phone / mAsset / template / created / updated / checkbox / relation / rollup / lineNumber`

`block` 是首列 (绑定文档块的标题列), 建库时自带, 通常不动。

## ⚠️ 值结构对照表 (最关键的坑, raw 底层用)

<<<<<<< HEAD
> **用 `siyuan av` 命令组则不需要手工构造** — `av add/update` 的 `--values '{字段名: 值}'` 会自动按字段类型嵌套 (select→mSelect 数组 / date→毫秒时间戳 / checkbox→布尔), 并在写后自动验证。
> 下表仅在使用 `raw database item update` 手工传 `--value` 时需要。

`database item update` 返回 `ok` **不代表值真写进去了**, 必须用 `database render` 验证。各字段类型 value 的 JSON 结构**必须按字段类型嵌套** (源码 `kernel/av/value.go` 的 ValueXxx 结构体决定):
=======
`database item update` 返回 `ok` **不代表值真写进去了**, 必须用 `database render` 验证 (3.8.0; 旧版用 `database get`)。各字段类型 value 的 JSON 结构**必须按字段类型嵌套** (源码 `kernel/av/value.go` 的 ValueXxx 结构体决定):
>>>>>>> gittree-wf-siyuan-w1-4

| 类型 | 正确 `--value` JSON | 错误写法 (CLI 会返回 ok 但不落库) |
|------|---------------------|------|
| text | `{"type":"text","text":{"content":"..."}}` | `{"type":"text","text":"..."}` (text 非 string) |
| url | `{"type":"url","url":{"content":"..."}}` | `{"type":"url","content":"..."}` (顶层 content 不生效) |
| email | `{"type":"email","email":{"content":"..."}}` | 同 url, 顶层 content 不生效 |
| phone | `{"type":"phone","phone":{"content":"..."}}` | 同上 |
| date | `{"type":"date","date":{"content":<Unix毫秒int>,"isNotEmpty":true}}` | `{"type":"date","content":"2026-07-08"}` (content 必须是时间戳) |
| select | `{"type":"select","mSelect":[{"content":"..."}]}` | `{"type":"select","content":"..."}` (**单选内部用 mSelect 数组!**) |
| mSelect | `{"type":"mSelect","mSelect":[{"content":"A"},{"content":"B"}]}` | `{"type":"mSelect","contents":["A"]}` |
| checkbox | `{"type":"checkbox","checkbox":{"checked":true}}` | `{"type":"checkbox","checked":true}` (顶层 checked 不生效) |
| template | `{"type":"template","template":{"content":"..."}}` | `{"type":"template","content":"..."}` |
| number | `{"type":"number","number":{"content":123,"isNotEmpty":true}}` | `{"type":"number","content":123}` (顶层 content 不生效) |
| relation | `{"type":"relation","relation":{"blockIDs":["<目标行blockID>"]}}` | relation.contents 是自动渲染的, 不需传 |
| mAsset | `{"type":"mAsset","mAsset":[{"type":"file","name":"名","content":"<url>"}]}` | type 为 file 或 image |

日期时间戳生成: `python3 -c "import calendar;print(int(calendar.timegm((2026,7,8,0,0,0,0,0,0)))*1000)"`

### 为什么会静默返回 ok (根因)

源码 `kernel/model/attribute_view.go` 的 `updateAttributeViewValue`: CLI 传来的 `--value` JSON 会被反序列化到 `*av.Value` 结构体。`av.Value` 的字段是嵌套对象 (`Text/URL/Date/MSelect/Checkbox/...`, json tag 为 `text/url/date/mSelect/checkbox/...`)。**如果 JSON 用了顶层 `content`/`checked` 等字段**, 因为 `Value` 结构体没有这些顶层字段, 反序列化时这些值被丢弃 → 对应子对象为 nil → 后续处理跳过 → **函数静默 return, CLI 照常打印 ok 但什么都不存**。这是 CLI bug, 未报错, 极易误判成功。

### select 选项的自动创建行为

源码逻辑: 写 select/mSelect 时, 若传入的选项 `content` 在该字段的 options 里不存在, **会自动新建选项并随机配色** (`color = 1~14 随机`), 不会报错。所以第一次写新选项值不需要预先建选项。但随机配色可能不符合预期, 重要选项建议先在思源 App 里手动建好并选好颜色。

### `--value` 里的 type 字段

`type` 字段会被反序列化并覆盖 val.Type, 但**实际写入类型以 keyID 对应的字段类型为准** (源码 `val.Type = keyValues.Key.Type` 在反序列化前已设置)。所以 type 写错不会改变字段类型, 但建议与字段实际类型保持一致避免混淆。

## 3.8.0 结构变更 (B1/B2, av 命令已适配)

- **B1 — `database keys` 输出从数组 → 对象包装**: 旧 (3.7) 直接返回字段数组; 新 (3.8) 返回 `{id, name, keys: [...]}`。**av keys 已适配** (兼容两种结构)。
- **B2 — `database get` 不再返回行数据**: `keyValues` 字段消失, get 只剩 `{id, name, keys, views}` 结构元数据。行数据改由 `database render` 提供: `view.rows[].id` = itemID(行ID), `view.rows[].cells[].value` = 单元格 (`keyID` 关联字段, `blockID` = 行ID, `block.id` = 绑定文档块 ID, detached 行带 `isDetached:true`)。**所有行数据读取/写入验证必须走 render** — av rows/get/verify/export/add/update/remove 已全部走 render。
- `render` 分页参数 `-p <页> -s <页大小>` (默认 50); av 命令内部自动翻页拉全量。

## itemID 与 blockID 的区别

- **blockID**: 绑定的文档块 ID (item add 时用 `--block` 传入的值), 是「首列主键」指向的文档。
- **itemID**: 数据库行的 ID, **每次 item add 时新生成** (`ast.NewNodeID()`), **不等于 blockID** (源码 AddAttributeViewBlock 第 3685 行)。detached 行同理也是新生成。
<<<<<<< HEAD
- **item add 不返回 itemID**: CLI 和 MCP 都只返回 `ok`/`item added`, 必须 render 反查。反查方法 (B2): `view.rows[].id` 即 itemID; block 类型单元格的 `value.block.id` 是绑定的文档块 ID。**av add 已自动反查** (--block 模式按文档 ID 精确匹配; detached 模式按标题匹配, 失败取行尾新行)。

## 录入一条记录的标准流程 (用 av 命令)

1. **先写好排查文档** (用 `write` 命令, 拿到 doc-id)
2. **加一行** (绑定文档): `siyuan av add <avID> --block <doc-id> --content "标题" --values '{...}'` — 输出新行 itemID, 已自动验证字段写入
3. **查字段名** (av 命令按字段名传值): `siyuan av keys <avID>`
4. **填值/改值**: `siyuan av update <avID> --row <itemID> --values '{字段名: 值}'` (写后自动验证)
5. **验证**: `siyuan av verify <avID>` 逐行看实际值

### av 命令的值规则 (`--values`)

`--values` 传 `{字段名: 值}` JSON, 值按字段类型自动嵌套:

| 字段类型 | 传值示例 | 自动构造 |
|------|------|------|
| text / url / email / phone / template | `"排查结论":"内容"` | `{text:{content}}` 等 |
| date | `"报告日期":"2026-07-08"` 或 `"2026-07-08T00:00:00Z"` 或毫秒数字 | `{date:{content:<毫秒>,isNotEmpty:true}}` |
| select (单选) | `"问题状态":"已解决"` | `{select,mSelect:[{content}]}` |
| mSelect (多选) | `"标签":["快速","耗时"]` 或 `"标签":"快速,耗时"` | `{mSelect,mSelect:[{content},...]}` |
| checkbox | `"是否修复":true` (或 `"true"`/`"1"`) | `{checkbox:{checked}}` |
| number | `"评分":95` | `{number:{content:95,isNotEmpty:true}}` |
| relation | `"关联":["<blockID>"]` 或逗号分隔串 | `{relation:{blockIDs:[...]}}` |
| mAsset | `"附件":["名1","名2"]` | `{mAsset:[{type:file,name,content:''}]}` |
| 完整 value 对象 | `{"字段":{"type":"text","text":{"content":"x"}}}` | 原样透传 |

未知字段名 / 只读类型 (rollup/created/updated/lineNumber) 会报错退出 1。block 主键列由 `--content`/`--block` 设置, values 里写它会被忽略并提示。
=======
- **item add 不返回 itemID**: CLI 和 MCP 都只返回 `ok`/`item added`, 必须反查。**3.8.0 反查用 `database render`**: 主键 block 列的 `view.rows[].cells[]` 中 type=block 的 `value.blockID` 即 itemID; 而 `value.block.id` 是绑定的文档块 ID。

## 录入一条记录的标准流程 (3.8.0)

1. **先写好排查文档** (用 `siyuan write` 命令, 拿到 doc-id)
2. **查字段结构** 拿 keyID: `siyuan raw database keys --av <avID> -f json` (3.8.0: 取 `.keys`)
3. **加一行** 绑定文档: `siyuan raw database item add --av <avID> --block <doc-id> --content "标题" -f json`
   - 返回 ok 但不返回 itemID, 用 `database render` 反查 (见上)
4. **逐字段填值** 用上表正确结构: `siyuan raw database item update --av <avID> --key <keyID> --item <itemID> --value '<json>'`
5. **验证**: `node scripts/av_ops.js verify <avID>` (ok 不代表成功)
>>>>>>> gittree-wf-siyuan-w1-4

## ⚠️ value 含双引号时的传参陷阱 (关键经验)

`--value '<json>'` 用单引号包裹时, JSON 内的双引号 + shell 引号嵌套极易出错, 导致 value 解析失败**静默不落库** (CLI 仍返回 ok)。这是重建排查记录库踩到的核心坑。

**根因**: shell 对 `'..."..."...'` 的引号处理与 JSON 内部双引号冲突, 传入内核的 value 字符串被截断或破坏, 反序列化到 av.Value 时子对象为 nil, 静默跳过。

**推荐做法 — 用 av 命令组** (无 shell 引号问题, 自动处理):
```bash
# 直接传 (值不含 shell 特殊字符时)
siyuan av add <avID> --values '{"排查结论":"结论内容"}' --content "标题"
# 含引号的值: 写到文件再引用, 或管道 stdin
cat > /tmp/val.json <<'EOF'
{"排查结论":"含\"引号\"的结论","责任人":"张三"}
EOF
siyuan av update <avID> --row <itemID> --values @/tmp/val.json
printf '%s' '{"排查结论":"含引号值"}' | siyuan av add <avID> --values -
```

**底层做法 (raw 手工传 value, 不推荐)**:

**做法 1 — 临时文件传递**:
```bash
VAL='{"type":"text","text":{"content":"含\"引号\"的内容"}}'
echo -n "$VAL" > /tmp/av_val.txt
siyuan raw database item update --av "$AV" --key <keyID> --item "$ITEM" \
  --value "$(cat /tmp/av_val.txt)"
```

**做法 2 — 用 av_ops.js 工具库** (JS 里无 shell 引号问题):
```javascript
const av = require('./scripts/av_ops.js');
av.setCellText(avID, keyID, itemID, '含"引号"的内容');  // 自动处理
```

<<<<<<< HEAD
## 工具库 scripts/av_ops.js (旧, 仅供旧脚本引用)
=======
## 工具库 scripts/av_ops.js (av 命令组核心, 推荐)
>>>>>>> gittree-wf-siyuan-w1-4

> **已迁移至 `siyuan av` 命令组** (能力等价: 自动嵌套/引号处理/写入验证), 新代码请用 av 命令。以下保留供引用旧脚本时对照。

CLI 和 require 两种用法:

```bash
# CLI 用法
node scripts/av_ops.js search "排查记录"        # 按名查 avID
node scripts/av_ops.js keys <avID>               # 列字段
node scripts/av_ops.js verify <avID>             # 打印所有行字段实际值 (验证写入)
node scripts/av_ops.js export <avID>             # 导出为 JSON (备份/迁移用)
```

```javascript
// require 用法 (批量操作推荐)
const av = require('./scripts/av_ops.js');
const AV = av.search('排查记录');

// 加行 + 填值 (一行代码搞定, 自动构造正确结构)
const itemId = av.addRow(AV, docId, '排查：XXX');
av.setCellSelect(AV, av.keyId(AV,'业务模块'), itemId, '调课调讲');  // select 自动用 mSelect
av.setCellDate(AV, av.keyId(AV,'报告日期'), itemId, '2026-07-08'); // 自动转毫秒时间戳
av.setCellText(AV, av.keyId(AV,'排查结论'), itemId, '含"引号"的结论'); // 自动处理引号
av.setCellCheckbox(AV, av.keyId(AV,'是否已修复'), itemId, true);

// 或批量填值
av.fillRow(AV, itemId, {
  '业务模块': '调课调讲',           // string 自动判 text
  '问题状态': '已解决',
  '排查结论': '结论内容',
  '是否已修复': true,               // boolean 自动判 checkbox
});

// 验证
av.verify(AV);
```

> **3.8.0 适配要点** (对应 COMPAT-REPORT-3.8.0.md 的 B1/B2): av_ops.js 内部数据访问按 3.8.0 结构处理 — `listKeys` 兼容对象包装 (`Array.isArray(out) ? out : out.keys`); 行数据 (itemID 反查 / verify / export) 从 `database get` 的 `keyValues` 改为 `database render` 的 `view.rows`。**对外接口不变** (search/keys/verify/export/addRow/setCellXxx/fillRow)。

便捷方法对照表 (自动构造正确嵌套结构, 无需记 JSON):

| 方法 | 对应字段类型 | 说明 |
|------|------------|------|
| `setCellText(avID,k,it,val)` | text | `{text:{content:val}}` |
| `setCellUrl(avID,k,it,val)` | url/email/phone | `{url:{content:val}}` |
| `setCellSelect(avID,k,it,opt)` | select | **自动用 mSelect 数组** (思源坑点) |
| `setCellMSelect(avID,k,it,opts[])` | mSelect | 多选 |
| `setCellDate(avID,k,it,'2026-07-08')` | date | **自动转 Unix 毫秒** |
| `setCellCheckbox(avID,k,it,bool)` | checkbox | `{checkbox:{checked:bool}}` |
| `fillRow(avID,it,{字段:值})` | 混合 | 自动判类型, 批量填 |

## 排查记录库字段设计 (当前规范)

库 avID: `20260709112905-e1gm9bd`, 位于 `/工作/供应链/问题排查记录/排查记录库`。

| 字段 | 类型 | 规范选项 / 说明 |
|------|------|----------------|
| 主键 | block | 绑定排查文档 |
| 报告日期 | date | 问题报告时间 (Unix 毫秒) |
| 业务模块 | select | 调课调讲/退课/进班分配/场次/班级管理/课程资料/接口/性能/运维/其他 |
| 问题类型 | select | 数据异常/状态不一致/接口报错/数据缺失/绑定未生效/数据校验/性能问题/配置错误/其他 |
| 严重程度 | select | P0阻断/P1功能/P2体验/P3建议 |
| 根因类型 | select | 系统bug/业务操作遗漏/数据问题/配置问题/环境问题/待定/非问题 |
| 问题状态 | select | 待排查/排查中/已解决/已关闭/已忽略 |
| 影响范围 | select | 单用户/多用户/全量/无影响 |
| 涉及接口 | url | 相关接口地址 |
| 涉及数据 | text | 工单号、表名等 (合并字段, 用 `\|` 分隔) |
| 排查结论 | text | 最终结论 (用 text 不用 template, template 是公式字段) |
| 责任人 | text | 排查/修复负责人 |
| 标签 | mSelect | 跨维度标签, 如「快速」「耗时」「需复盘」 |

设计要点:
- 「是否系统bug」归入根因类型 (系统bug), 不单独设字段
- 「是否已修复」归入问题状态 (已解决/已关闭), 统一状态流转
- select 选项首次写入会自动创建并随机配色, 重要选项建议先在 App 里手动建好配色
- 排查结论用 text 而非 template (template 是公式字段, 不能存自由文本)

## 完整录入示例 (排查记录库, av 命令)

```bash
AV=20260709112905-e1gm9bd  # 排查记录库
# 或动态查: AV=$(siyuan av list | grep 排查 | cut -f1)

# 1. 查字段名 (av 命令按字段名传值)
siyuan av keys "$AV"

# 2. 先写排查文档 (拿到 DOC_ID), 建议挂到对应业务子目录
DOC=$(cat report.md | siyuan write --notebook 工作 --title "排查：XXX" --parent-id "<业务子目录id>")

# 3. 加一行绑定文档 + 填值 (自动反查 itemID, 写后自动验证)
ITEM=$(siyuan av add "$AV" --block "$DOC" --content "排查：XXX" \
  --values '{"报告日期":"2026-07-08","业务模块":"调课调讲","问题类型":"状态不一致","问题状态":"已解决"}')

# 4. 追加/修改更多字段 (含引号的值走 @file 或 stdin)
cat > /tmp/v.json <<'EOF'
{"排查结论":"含\"引号\"的结论","标签":["快速","需复盘"],"责任人":"张三"}
EOF
siyuan av update "$AV" --row "$ITEM" --values @/tmp/v.json

<<<<<<< HEAD
# 5. ⚠️ 验证 (写入以实际值为准, ok 不代表成功)
siyuan av verify "$AV"
# 或单行: siyuan av get "$AV" --row "$ITEM"
=======
# 5. ⚠️ 验证 (ok 不代表成功, 必须查实际值; 3.8.0 用 render 取行数据)
node scripts/av_ops.js verify "$AV" | head -30
>>>>>>> gittree-wf-siyuan-w1-4
```
