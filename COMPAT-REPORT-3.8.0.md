# SiYuan-Kernel 3.8.0 兼容性报告

> 任务: siyuan-fix wave1 step3 (验证 skill 与 3.8.0 兼容性)
> 验证方式: 对实际安装内核 `/Applications/SiYuan.app/Contents/Resources/kernel/SiYuan-Kernel` (v3.8.0) 逐一执行 `--help` 比对 + 只读冒烟。
> 日期: 2026-08-16

## 结论

skill 文档与封装层引用的**全部命令参数在 3.8.0 下无失效/变更**（26 个封装子命令、4 大核心组全子命令、其余 14 组抽查均存在且参数兼容）。
但发现 **2 处输出结构 breaking 变更**，影响 `scripts/av_ops.js` 与 `references/database.md` 的验证流程（数据库相关）。版本声明有 2 处明确过期。

---

## 一、命令参数核对（无 breaking）

### notebook / document / block / database 四大组（全子命令逐一比对 --help）

| 组 | 文档引用子命令 | 3.8.0 状态 | 备注 |
|---|---|---|---|
| notebook | list / create / remove / rename / open / close / set-icon / random-icon | ✅ 全部存在 | list 无参数变化 |
| document | search / list / get / info / rename / duplicate / remove / move / create | ✅ 全部存在，参数一致 | list 新增 `--hpath`（向后兼容）；move 仍为 `--id --notebook [--path --hpath]` 跨笔记本 |
| block | append / update / delete / insert / children / kramdown / prepend / move / get / breadcrumb / dom / stat / batch-get / batch-kramdown | ✅ 全部存在，参数一致 | update 新增 `--lock-type`；kramdown 新增 `--mode md\|textmark`；insert 仍 `--parent` 必填 + `--previous` 锚点 |
| database | search / get / keys / key add / key remove / item add / item update / item remove / render | ✅ 全部存在，参数一致 | item add 新增 `--group/--ignore-default-fill/--previous/--view`；key add 新增 `--icon/--prev`；key remove 新增 `--remove-relation-dest`；render 新增 `--query/--view`（均向后兼容） |

### 其余组抽查（存在性 + 关键参数）

attr / bookmark / tag / dailynote / file / export / import / asset / history / inbox / template / repo / sync / system / workspace / search / ref / outline —— 全部存在。
- `attr set --id --attr name=value` ✅（--attr 变 stringArray 可重复，兼容）
- `export md --id`、`export docx --id --output`（output 必填）✅
- `import md --file --notebook`、`import sy` ✅
- `asset upload --id --file` ✅（--file 变 stringArray 可重复，兼容）
- `ref backlinks --id [--keyword]` ✅（新增 `--sort`，兼容）
- 全局新增 `--dry-run`（兼容，不影响）

**无失效参数。** 文档中所有 `siyuan raw ...` / 封装命令参数均可在 3.8.0 使用。

---

## 二、输出结构变更（2 处 breaking，需修复/更新）

### B1. `database keys` 输出从数组 → 对象包装

- 旧 (3.7): `[...]` 字段数组
- 新 (3.8): `{"id": "<avID>", "name": "<库名>", "keys": [...]}`（keys 才是字段数组）
- **影响**: `scripts/av_ops.js` `listKeys()` / `keyId()` 直接 `JSON.parse(out)` 后 `.find/.map` → 报错 `listKeys(...).map is not a function`
- 实测报错: `node scripts/av_ops.js keys 20260709112905-e1gm9bd` → `Error: listKeys(...).map is not a function`
- **修复方向**: listKeys 返回 `data.keys`（需兼容判断：`Array.isArray(out) ? out : out.keys`）

### B2. `database get` 不再返回行数据（keyValues 字段消失）

- 旧 (3.7): `database get` 返回含 `keyValues`（每字段的 values 数组，含行数据）
- 新 (3.8): `database get` 仅返回 `{id, name, keys, views}`（结构元数据，**无行数据**）
- 行数据改由 `database render` 提供: `view.rows[].id` = itemID(行ID)，`view.rows[].cells[].value` = `{keyID, blockID, type, ...}`（单元格值，blockID 为绑定文档块 ID）
- **影响**: `av_ops.js` `findItemIdByDoc()` / `addDetachedRow()` / `verify()` 依赖 `data.keyValues` → 全部失效（`.find` 于 undefined）
- **影响**: `references/database.md` 的「item add 后 `database get` 反查 itemID」「写入后用 `database get` 验证」两处流程描述失效，需改为 `database render`
- **修复方向**: av_ops.js 内部数据获取从 `get` 改为 `render`（取 `view.rows`）；database.md 更新反查/验证流程

> 注: `database render` 的参数（--av/-p/-s/--query/--view）与 3.8.0 完全一致，是替代 `get` 做数据读取的正确入口。

---

## 三、版本声明检查（需更新的位置）

| 文件:行 | 当前声明 | 判断 |
|---|---|---|
| SKILL.md:156 | `(v3.7.0)` 内核版本 | ❌ **不准确** — 实际安装 3.8.0，应更新为 `(v3.8.0)` |
| references/commands.md:3 | `数据来源: 源码 kernel/cli/cmd/*.go (SiYuan-Kernel v3.7.0)` | ❌ **不准确/过期** — 命令表已按 3.8.0 验证，应更新为 3.8.0 |
| SKILL.md:6 (frontmatter description) | `基于 SiYuan-Kernel 3.7+ CLI 封装` | ⚠️ 语义准确（3.7+ 涵盖 3.8），但按"已验证版本"策略建议改 3.8+；若保留 3.7+ 需说明 3.8 已验证 |
| README.md:3 | `基于 [SiYuan-Kernel 3.7+](...)` | ⚠️ 同上 |
| bin/siyuan:2 (注释) | `基于 SiYuan-Kernel 3.7+` | ⚠️ 同上 |
| bin/siyuan:505 (usage) | `基于 SiYuan-Kernel 3.7+` | ⚠️ 同上 |
| references/conventions.md | 无版本声明 | ✅ 无需更新 |
| references/database.md | 无版本声明 | ✅ 无需更新（但 B2 影响其流程描述） |

---

## 四、冒烟测试（3.8.0，只读）

| 链路 | 结果 |
|---|---|
| `siyuan notebooks` | ✅ JSON 正常（工作/学习/生活） |
| `siyuan list 工作` | ✅ 中文名解析 + 文档列表（id/name/子数/path） |
| `siyuan search "调课"` | ✅ `doc_id<TAB>hpath<TAB>notebook` 格式正确 |
| `siyuan read <doc-id>` | ✅ markdown 源输出（含 frontmatter） |
| `siyuan sql` / `get` / `outline` / `children` | ✅ 均正常 |
| `siyuan raw database search` | ✅ 返回 avID |
| `node scripts/av_ops.js search "排查"` | ✅ 正常 |
| `node scripts/av_ops.js keys <avID>` | ❌ 受 B1 影响（见上） |
| `node scripts/av_ops.js verify <avID>` | ❌ 受 B2 影响（见上） |

**结论**: 基本读写链路（notebooks/list/search/read/sql/get/outline/children）在 3.8.0 全部正常；数据库工具链 av_ops.js 因 B1/B2 结构变更需修复（建议作为独立修复任务，不在本验证任务内改动代码）。

---

## 五、建议的后续修复项（供排期）

1. **av_ops.js 适配 3.8.0**：`listKeys` 兼容对象包装；`findItemIdByDoc`/`addDetachedRow`/`verify` 改用 `database render` 取行数据
2. **database.md 更新**：「item add 反查 itemID」「验证写入」两处流程由 `database get` 改为 `database render`，并补充 `get` 结构变更说明
3. **版本声明更新**：SKILL.md:156、references/commands.md:3 更新为 3.8.0；4 处 "3.7+" 建议按策略统一
