#!/usr/bin/env bash
# siyuan av 子命令组 (属性视图 / 数据库): list / keys / rows / get / add / update /
#   remove / verify / export
#
# 适配 SiYuan-Kernel 3.8.0 breaking 变更:
#   B1: database keys 输出为 {id,name,keys:[]} 对象 (兼容 3.7 旧数组, fmt.js 兼容判断)
#   B2: database get 不再返回行数据 (keyValues 消失), 行数据由 database render 提供
#       (view.rows[].id = itemID, cells[].value 含 keyID/blockID) → 所有行数据读取与
#       写入验证均走 render
# 硬约束:
#   ① 值按字段类型自动嵌套 (select 用 mSelect 数组 / date 用毫秒时间戳), 含引号值
#      支持 --values @file 或 stdin;
#   ② item update / item add 的 "ok" 不可信, 所有写操作后 render 验证真实生效;
#   ③ 原 scripts/av_ops.js 能力已迁移至此 (av_ops.js 保留供旧脚本引用)。

# av 组帮助 (bin/siyuan 的 sy_usage av 调用)
av_usage() { # [子命令]
  case "${1:-}" in
    list)
        cat <<'EOF'
用法: siyuan av list [--json|--markdown]
    列出全部数据库 (名称+avID+所在路径); --markdown 表格
EOF
        ;;
    keys)
        cat <<'EOF'
用法: siyuan av keys <avID|库名> [--json|--markdown]
    列字段 (name, type, keyID; 3.8.0 keys 为 {id,name,keys:[]} 对象, 已适配 B1)
    --markdown 表格
EOF
        ;;
    rows)
        cat <<'EOF'
用法: siyuan av rows <avID|库名> [--limit N] [-H] [--json|--markdown]
    列行数据 (走 database render, 适配 B2); 文本=TSV 可管道: itemID<TAB>标题<TAB>字段值...
    -H 输出表头; --json 输出 [{itemID,title,fields:{字段名:值}}]; --markdown 表格
EOF
        ;;
    get)
        cat <<'EOF'
用法: siyuan av get <avID|库名> --row <rowID> [--json|--markdown]
    单行详情 (标题 + 每字段实际值); --markdown 键值表
EOF
        ;;
    add)
        cat <<'EOF'
用法: siyuan av add <avID|库名> --values '<JSON>' [--content <标题>] [--block <doc-id>] [--json|--markdown]
    加一行 (默认游离行; --block 绑定文档块)。--values 为 {字段名: 值} JSON,
    值按字段类型自动嵌套 (select 用 mSelect / date 自动转毫秒 / checkbox 布尔)。
    含引号的值用 --values @file 或管道 stdin 传入。输出新行 itemID (文本) /
    JSON {id,action} / markdown 确认块。
EOF
        ;;
    update)
        cat <<'EOF'
用法: siyuan av update <avID|库名> --row <rowID> --values '<JSON>' [--json|--markdown]
    改行字段 (同 add 的值规则)。item update 的 ok 不可信, 写后 render 验证,
    验证失败退出 1 并提示实际值。
EOF
        ;;
    remove)
        cat <<'EOF'
用法: siyuan av remove <avID|库名> --row <rowID> [--json|--markdown]
    删行, 删后 render 验证行已消失
EOF
        ;;
    verify)
        cat <<'EOF'
用法: siyuan av verify <avID|库名> [--json|--markdown]
    逐行打印所有字段实际值 (验证写入的权威入口; 替代原 av_ops.js verify)
    --markdown 表格
EOF
        ;;
    export) cat <<'EOF'
用法: siyuan av export <avID|库名>
  导出全量 JSON (备份/迁移): [{itemID,docID,title,fields:{字段名:值}}]
EOF
;;
    *) cat <<'EOF'
siyuan av — 数据库 (属性视图) 子命令组 (适配 SiYuan-Kernel 3.8.0 B1/B2)

  av list [--json|--markdown]    列出全部数据库 (名称+avID)
  av keys <avID> [--json|--markdown]   列字段 (3.8 keys 对象包装已适配)
  av rows <avID> [--limit N] [-H] [--json|--markdown]   列行数据 (走 render, TSV 可管道)
  av get <avID> --row <ID> [--json|--markdown]   单行详情
  av add <avID> --values '<JSON>' [--content <标题>] [--block <doc-id>] [--json|--markdown]
                            加行 (值按字段类型自动嵌套; @file/stdin 传含引号值)
  av update <avID> --row <ID> --values '<JSON>' [--json|--markdown]   改行 (写后 render 验证)
  av remove <avID> --row <ID> [--json|--markdown]   删行 (删后验证)
  av verify <avID> [--json|--markdown]   逐行打印实际值 (验证权威入口)
  av export <avID>           导出全量 JSON (备份, 不参与输出模式)

<avID|库名> 支持传 avID 或库名 (模糊搜首个匹配)。写操作后均 render 验证真实生效。
EOF
    ;;
  esac
}

# 解析 avID 引用 (id 或名称) -> stdout: avID; 失败 sy_die
sy_av_resolve() { # <ctx> <引用>
  local ctx="$1" ref="$2"
  if [[ "$ref" =~ ^[0-9]{14}-[a-z0-9]+$ ]]; then
    echo "$ref"
    return 0
  fi
  local out id
  out="$(sy_json "$ctx" database search "$ref")" || return $?
  id="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" find-by-field avName "$ref" avID)"
  if [[ -z "$id" ]]; then
    sy_die 1 "$ctx: 找不到数据库 '$ref'" "运行 'siyuan av list' 查看全部数据库 (支持传 avID 或库名)"
  fi
  echo "$id"
}

# 全量 render (自动翻页; limit>0 时只取前 limit 行) -> stdout: 合并后的 render JSON
sy_av_render_all() { # <ctx> <avID> [limit]
  local ctx="$1" av="$2" limit="${3:-0}"
  local size=500 page=1 out rowcount got pages=()
  [[ $limit -gt 0 && $limit -lt $size ]] && size=$limit
  while :; do
    out="$(sy_json "$ctx" database render --av "$av" -p "$page" -s "$size")" || return $?
    rowcount="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-rowcount)" || return $?
    pages+=("$out")
    got=$((page * size))
    if [[ $got -ge ${rowcount:-0} ]]; then
      break
    fi
    page=$((page + 1))
    [[ $page -gt 200 ]] && break
  done
  if [[ ${#pages[@]} -eq 1 ]]; then
    echo "${pages[0]}"
  else
    local arr="[" p
    for p in "${pages[@]}"; do arr+="$p,"; done
    arr="${arr%,}]"
    printf '%s' "$arr" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-merge
  fi
}

# 读取 --values: '<JSON>' | @file | '-' | stdin -> stdout: JSON 字符串
sy_av_read_values() { # <raw>  (空 = stdin)
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    if [[ -t 0 ]]; then
      sy_die 2 "av: 缺少 --values" "传 '{字段:值}' JSON, 或 --values @file / 管道 stdin (含引号值用后两者)"
    fi
    cat
  elif [[ "$raw" == "-" ]]; then
    cat
  elif [[ "$raw" == @* ]]; then
    cat "${raw#@}"
  else
    printf '%s' "$raw"
  fi
}

# 用户 values JSON + keys JSON -> stdout: [{keyID,name,type,value,expect}] (构建失败 stderr 可见)
sy_av_build() { # <ctx> <values_json> <keys_json>
  local ctx="$1" values="$2" keys="$3"
  printf '%s' "$values" | SY_AV_KEYS="$keys" "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-build
}

# 逐字段写入 + render 验证 (item update 的 ok 不可信) -> stdout: "ok"; 验证失败 sy_die 1
sy_av_apply() { # <ctx> <av> <itemID> <built_json>
  local ctx="$1" av="$2" item="$3" built="$4"
  local n i kv keyID value rc=0
  n="$(echo "$built" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" len)" || return $?
  for ((i = 0; i < n; i++)); do
    kv="$(echo "$built" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" idx "$i")" || return $?
    keyID="$(echo "$kv" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" field keyID)"
    value="$(echo "$kv" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" field-json value)"
    sy_kernel database item update --av "$av" --key "$keyID" --item "$item" --value "$value" >/dev/null || return $?
  done
  # render 验证每个字段真实生效
  local rd chk expect
  rd="$(sy_av_render_all "$ctx" "$av")" || return $?
  for ((i = 0; i < n; i++)); do
    kv="$(echo "$built" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" idx "$i")"
    keyID="$(echo "$kv" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" field keyID)"
    expect="$(echo "$kv" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" field expect)"
    chk="$(echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render check-cell "$item" "$keyID" "$expect")"
    if [[ "$chk" != ok* ]]; then
      echo "siyuan $ctx: 字段 '$keyID' 写入验证失败: 期望 [$expect], 实际 [${chk#FAIL	}]" >&2
      rc=1
    fi
  done
  if [[ $rc -ne 0 ]]; then
    sy_die 1 "$ctx: 写入未生效 (CLI 返回 ok 但值未落库)" "运行 'siyuan av verify $av' 查看当前实际值"
  fi
  echo "ok"
}

# ---------------------------------------------------------------------------
# av list [--json] — 列出全部数据库
# ---------------------------------------------------------------------------
cmd_av_list() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      av_usage list
      return 0
      ;;
    *) sy_die 2 "av list: 未知参数 '$1'" "用法: siyuan av list [--json|--markdown]" ;;
    esac
  done
  local out
  out="$(sy_json "av list" database search "")" || return $?
  case "$SY_MODE" in
  json)
    echo "$out"
    ;;
  markdown)
    # 表格: 名称 | avID | 路径
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-list-md
    ;;
  *)
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-search-text
    ;;
  esac
}

# ---------------------------------------------------------------------------
# av keys <avID> [--json] — 列字段 (适配 B1)
# ---------------------------------------------------------------------------
cmd_av_keys() {
  local av=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      av_usage keys
      return 0
      ;;
    -*) sy_die 2 "av keys: 未知参数 '$1'" "用法: siyuan av keys <avID|库名> [--json|--markdown]" ;;
    *)
      if [[ -z "$av" ]]; then
        av="$1"
      else
        sy_die 2 "av keys: 多余参数 '$1'" "用法: siyuan av keys <avID|库名> [--json|--markdown]"
      fi
      shift
      ;;
    esac
  done
  [[ -n "$av" ]] || sy_die 2 "av keys: 缺少 avID" "用法: siyuan av keys <avID|库名> [--json|--markdown] (用 'siyuan av list' 查 avID)"
  av="$(sy_av_resolve "av keys" "$av")" || return $?
  local out
  out="$(sy_json "av keys" database keys --av "$av")" || return $?
  case "$SY_MODE" in
  json)
    echo "$out"
    ;;
  markdown)
    # 表格: 字段名 | 类型 | keyID (B1 对象包装先归一化)
    local rows
    rows="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-keys-rows)" || return $?
    echo "$rows" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-table 字段名:name 类型:type keyID:id
    ;;
  *)
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-keys-text
    ;;
  esac
}

# ---------------------------------------------------------------------------
# av rows <avID> [--limit N] [-H] [--json] — 列行数据 (适配 B2, 走 render)
# ---------------------------------------------------------------------------
cmd_av_rows() {
  local av="" limit=0 header=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    --limit | -l)
      limit="${2:?}"
      [[ "$limit" =~ ^[0-9]+$ ]] || sy_die 2 "av rows: --limit 必须是数字, 收到 '$limit'" "用法: siyuan av rows <avID|库名> [--limit N] [-H] [--json|--markdown]"
      shift 2
      ;;
    --header | -H)
      header=1
      shift
      ;;
    -h | --help)
      av_usage rows
      return 0
      ;;
    -*) sy_die 2 "av rows: 未知参数 '$1'" "用法: siyuan av rows <avID|库名> [--limit N] [-H] [--json|--markdown]" ;;
    *)
      if [[ -z "$av" ]]; then
        av="$1"
      else
        sy_die 2 "av rows: 多余参数 '$1'" "用法: siyuan av rows <avID|库名> [--limit N] [-H] [--json|--markdown]"
      fi
      shift
      ;;
    esac
  done
  [[ -n "$av" ]] || sy_die 2 "av rows: 缺少 avID" "用法: siyuan av rows <avID|库名> [--limit N] [-H] [--json|--markdown]"
  av="$(sy_av_resolve "av rows" "$av")" || return $?
  local rd
  rd="$(sy_av_render_all "av rows" "$av" "$limit")" || return $?
  case "$SY_MODE" in
  json)
    echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render rows-json "$limit"
    ;;
  markdown)
    # 表格: itemID | 标题 | 各字段 (列 = 可见字段)
    echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render rows-md "$limit"
    ;;
  *)
    echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render rows "$limit" "$header"
    ;;
  esac
}

# ---------------------------------------------------------------------------
# av get <avID> --row <rowID> [--json] — 单行详情
# ---------------------------------------------------------------------------
cmd_av_get() {
  local av="" row=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    --row | -r)
      row="${2:?}"
      shift 2
      ;;
    -h | --help)
      av_usage get
      return 0
      ;;
    -*) sy_die 2 "av get: 未知参数 '$1'" "用法: siyuan av get <avID|库名> --row <rowID> [--json|--markdown]" ;;
    *)
      if [[ -z "$av" ]]; then
        av="$1"
      else
        sy_die 2 "av get: 多余参数 '$1'" "用法: siyuan av get <avID|库名> --row <rowID> [--json|--markdown]"
      fi
      shift
      ;;
    esac
  done
  [[ -n "$av" ]] || sy_die 2 "av get: 缺少 avID" "用法: siyuan av get <avID|库名> --row <rowID> [--json|--markdown]"
  [[ -n "$row" ]] || sy_die 2 "av get: 缺少 --row" "用法: siyuan av get <avID|库名> --row <rowID> [--json|--markdown] (rowID 用 'siyuan av rows' 查看)"
  av="$(sy_av_resolve "av get" "$av")" || return $?
  local rd
  rd="$(sy_av_render_all "av get" "$av")" || return $?
  case "$SY_MODE" in
  json)
    echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render row-json "$row"
    ;;
  markdown)
    # 键值表: 项目 | 值 (行 ID/标题/每字段)
    echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render row-md "$row"
    ;;
  *)
    echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render row "$row"
    ;;
  esac
}

# ---------------------------------------------------------------------------
# av add <avID> --values '<JSON>' [--content <标题>] [--block <doc-id>]
#   item add 不返回 itemID → render 反查 (B2); 字段写入后 render 验证
# ---------------------------------------------------------------------------
cmd_av_add() {
  local av="" values_raw="" content="" block=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --values | -v)
      [[ -n "$values_raw" ]] && sy_die 2 "av add: 重复 --values" "用法: siyuan av add <avID|库名> --values '<JSON>' (或 --values @file / stdin)"
      values_raw="${2:?}"
      shift 2
      ;;
    --content | -c)
      content="${2:?}"
      shift 2
      ;;
    --block | -b)
      block="${2:?}"
      shift 2
      ;;
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      av_usage add
      return 0
      ;;
    -*) sy_die 2 "av add: 未知参数 '$1'" "用法: siyuan av add <avID|库名> --values '<JSON>' [--content <标题>] [--block <doc-id>] [--json|--markdown]" ;;
    *)
      if [[ -z "$av" ]]; then
        av="$1"
      else
        sy_die 2 "av add: 多余参数 '$1'" "用法: siyuan av add <avID|库名> --values '<JSON>' [--content <标题>] [--block <doc-id>]"
      fi
      shift
      ;;
    esac
  done
  [[ -n "$av" ]] || sy_die 2 "av add: 缺少 avID" "用法: siyuan av add <avID|库名> --values '<JSON>'"
  if [[ -z "$values_raw" && -t 0 ]]; then
    sy_die 2 "av add: 缺少 --values" "传 '{字段:值}' JSON, 或 --values @file / 管道 stdin (含引号值用后两者)"
  fi
  av="$(sy_av_resolve "av add" "$av")" || return $?

  local keys values_json built
  keys="$(sy_json "av add" database keys --av "$av")" || return $?
  values_json="$(sy_av_read_values "$values_raw")" || return $?
  built="$(sy_av_build "av add" "$values_json" "$keys")" || return $?

  # 反查基准: add 前行数 (新行若无法按标题匹配, 取行尾新行)
  local before_rc
  before_rc="$(sy_av_render_all "av add" "$av" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-rowcount)" || return $?

  # item add (默认游离行; --block 绑定文档块)
  local iargs=(database item add --av "$av")
  if [[ -n "$block" ]]; then
    iargs+=(--block "$block")
  else
    iargs+=(--detached)
  fi
  iargs+=(--content "$content")
  sy_kernel_or_die "av add" "${iargs[@]}" >/dev/null

  # render 反查 itemID (B2: row.id / block 单元格的 blockID)
  #   --block 模式: 按绑定的文档块 id 反查 (绑定后标题会被文档标题覆盖, content 匹配不可靠)
  #   detached 模式: 按标题匹配, 失败时取行尾新行 (add 前总行数即新行下标)
  local rd item
  rd="$(sy_av_render_all "av add" "$av")" || return $?
  if [[ -n "$block" ]]; then
    item="$(echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render find-item-by-doc "$block")"
    [[ -n "$item" ]] || sy_die 1 "av add: 无法反查新行 itemID (文档绑定未生效)" "运行 'siyuan av rows $av' 查看当前行"
  else
    item="$(echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render find-item "$content")"
    if [[ -z "$item" ]]; then
      item="$(echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render row-at "$before_rc")"
    fi
    [[ -n "$item" ]] || sy_die 1 "av add: 无法反查新行 itemID" "运行 'siyuan av rows $av' 查看当前行"
  fi

  sy_av_apply "av add" "$av" "$item" "$built" >/dev/null || return $?
  case "$SY_MODE" in
  json)
    printf '%s' "$item" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" json-ok-row "$item" 添加
    ;;
  markdown)
    printf '%s' "$item" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ok-row "$item" 添加
    ;;
  *)
    echo "$item"
    ;;
  esac
}

# ---------------------------------------------------------------------------
# av update <avID> --row <rowID> --values '<JSON>'
# ---------------------------------------------------------------------------
cmd_av_update() {
  local av="" row="" values_raw=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --values | -v)
      [[ -n "$values_raw" ]] && sy_die 2 "av update: 重复 --values" "用法: siyuan av update <avID|库名> --row <rowID> --values '<JSON>' (或 --values @file / stdin)"
      values_raw="${2:?}"
      shift 2
      ;;
    --row | -r)
      row="${2:?}"
      shift 2
      ;;
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      av_usage update
      return 0
      ;;
    -*) sy_die 2 "av update: 未知参数 '$1'" "用法: siyuan av update <avID|库名> --row <rowID> --values '<JSON>' [--json|--markdown]" ;;
    *)
      if [[ -z "$av" ]]; then
        av="$1"
      else
        sy_die 2 "av update: 多余参数 '$1'" "用法: siyuan av update <avID|库名> --row <rowID> --values '<JSON>'"
      fi
      shift
      ;;
    esac
  done
  [[ -n "$av" ]] || sy_die 2 "av update: 缺少 avID" "用法: siyuan av update <avID|库名> --row <rowID> --values '<JSON>'"
  [[ -n "$row" ]] || sy_die 2 "av update: 缺少 --row" "用法: siyuan av update <avID|库名> --row <rowID> --values '<JSON>'"
  if [[ -z "$values_raw" && -t 0 ]]; then
    sy_die 2 "av update: 缺少 --values" "传 '{字段:值}' JSON, 或 --values @file / 管道 stdin"
  fi
  av="$(sy_av_resolve "av update" "$av")" || return $?

  local keys values_json built rd has
  keys="$(sy_json "av update" database keys --av "$av")" || return $?
  values_json="$(sy_av_read_values "$values_raw")" || return $?
  built="$(sy_av_build "av update" "$values_json" "$keys")" || return $?

  # 确认行存在
  rd="$(sy_av_render_all "av update" "$av")" || return $?
  has="$(echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render has-row "$row")"
  [[ "$has" == ok ]] || sy_die 1 "av update: 找不到行 '$row'" "运行 'siyuan av rows $av' 查看行 id"

  if [[ "$SY_MODE" == "text" ]]; then
    sy_av_apply "av update" "$av" "$row" "$built" || return $?
  else
    # --json/--markdown: 抑制 "ok" (stdout 只含模式输出)
    sy_av_apply "av update" "$av" "$row" "$built" >/dev/null || return $?
  fi
  case "$SY_MODE" in
  json)
    printf '%s' "$row" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" json-ok-row "$row" 更新
    ;;
  markdown)
    printf '%s' "$row" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ok-row "$row" 更新
    ;;
  *)
    : # 文本模式维持原行为 (无输出)
    ;;
  esac
}

# ---------------------------------------------------------------------------
# av remove <avID> --row <rowID> — 删行, 删后 render 验证
# ---------------------------------------------------------------------------
cmd_av_remove() {
  local av="" row=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --row | -r)
      row="${2:?}"
      shift 2
      ;;
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      av_usage remove
      return 0
      ;;
    -*) sy_die 2 "av remove: 未知参数 '$1'" "用法: siyuan av remove <avID|库名> --row <rowID> [--json|--markdown]" ;;
    *)
      if [[ -z "$av" ]]; then
        av="$1"
      else
        sy_die 2 "av remove: 多余参数 '$1'" "用法: siyuan av remove <avID|库名> --row <rowID>"
      fi
      shift
      ;;
    esac
  done
  [[ -n "$av" ]] || sy_die 2 "av remove: 缺少 avID" "用法: siyuan av remove <avID|库名> --row <rowID>"
  [[ -n "$row" ]] || sy_die 2 "av remove: 缺少 --row" "用法: siyuan av remove <avID|库名> --row <rowID> (rowID 用 'siyuan av rows' 查看)"
  av="$(sy_av_resolve "av remove" "$av")" || return $?

  local rd has
  rd="$(sy_av_render_all "av remove" "$av")" || return $?
  has="$(echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render has-row "$row")"
  [[ "$has" == ok ]] || sy_die 1 "av remove: 找不到行 '$row'" "运行 'siyuan av rows $av' 查看行 id"

  sy_kernel_or_die "av remove" database item remove --av "$av" --ids "$row" >/dev/null

  # 删后验证行已消失
  rd="$(sy_av_render_all "av remove" "$av")" || return $?
  has="$(echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render has-row "$row")"
  [[ "$has" == none ]] || sy_die 1 "av remove: 删除未生效 (行 '$row' 仍在)" "重试, 或运行 'siyuan av verify $av' 查看实际行"
  case "$SY_MODE" in
  json)
    printf '%s' "$row" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" json-ok-row "$row" 删除
    ;;
  markdown)
    printf '%s' "$row" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ok-row "$row" 删除
    ;;
  *)
    echo "ok"
    ;;
  esac
}

# ---------------------------------------------------------------------------
# av verify <avID> [--json] — 逐行打印实际值 (验证权威入口)
# ---------------------------------------------------------------------------
cmd_av_verify() {
  local av=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      av_usage verify
      return 0
      ;;
    -*) sy_die 2 "av verify: 未知参数 '$1'" "用法: siyuan av verify <avID|库名> [--json|--markdown]" ;;
    *)
      if [[ -z "$av" ]]; then
        av="$1"
      else
        sy_die 2 "av verify: 多余参数 '$1'" "用法: siyuan av verify <avID|库名> [--json|--markdown]"
      fi
      shift
      ;;
    esac
  done
  [[ -n "$av" ]] || sy_die 2 "av verify: 缺少 avID" "用法: siyuan av verify <avID|库名> [--json|--markdown]"
  av="$(sy_av_resolve "av verify" "$av")" || return $?
  local rd
  rd="$(sy_av_render_all "av verify" "$av")" || return $?
  case "$SY_MODE" in
  json)
    echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render verify-json
    ;;
  markdown)
    # 表格: 全部行全部字段
    echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render verify-md
    ;;
  *)
    echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render verify
    ;;
  esac
}

# ---------------------------------------------------------------------------
# av export <avID> — 导出全量 JSON (备份)
# ---------------------------------------------------------------------------
cmd_av_export() {
  local av="${1:-}"
  if [[ "$av" == "-h" || "$av" == "--help" ]]; then
    av_usage export
    return 0
  fi
  [[ -n "$av" ]] || sy_die 2 "av export: 缺少 avID" "用法: siyuan av export <avID|库名>"
  av="$(sy_av_resolve "av export" "$av")" || return $?
  local rd
  rd="$(sy_av_render_all "av export" "$av")" || return $?
  echo "$rd" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" av-render export
}

# ---------------------------------------------------------------------------
# av 子命令分发
# ---------------------------------------------------------------------------
cmd_av() {
  local sub="${1:-}"
  if [[ $# -gt 0 ]]; then shift; fi
  case "$sub" in
  list | keys | rows | get | add | update | remove | verify | export)
    "cmd_av_$sub" "$@"
    ;;
  -h | --help | help)
    av_usage
    ;;
  *)
    if [[ -z "$sub" ]]; then
      av_usage
      return 0
    fi
    sy_die 2 "av: 未知子命令 '$sub'" "用法: siyuan av list|keys|rows|get|add|update|remove|verify|export (详见 siyuan help av)"
    ;;
  esac
}
