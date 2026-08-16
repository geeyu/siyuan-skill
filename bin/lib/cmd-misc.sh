#!/usr/bin/env bash
# siyuan 其他命令: sql / raw / raw-help / children / backlinks

# ---------------------------------------------------------------------------
# sql "<语句>" [-l N] [--json]
#   SQL 查询 (透传内核 sql, 默认 limit 100); 文本=TSV 行 (无表头, 可组合)
# ---------------------------------------------------------------------------
cmd_sql() {
  local limit=100 header=0
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -l | --limit)
      limit="${2:?}"
      shift 2
      ;;
    -H | --header)
      header=1
      shift
      ;;
    -h | --help)
      sy_usage sql
      return 0
      ;;
    -*) sy_die 2 "sql: 未知参数 '$1'" "用法: siyuan sql \"<语句>\" [-l N] [-H] [--json|--markdown]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "sql: 缺少 SQL 语句" "用法: siyuan sql \"<statement>\" [-l N] [--json|--markdown] (例: siyuan sql \"SELECT id,hpath FROM blocks WHERE type='d' LIMIT 5\")"
  local stmt="${args[0]}"
  local out
  out="$(sy_json sql sql "$stmt" -l "$limit")" || return $?
  case "$SY_MODE" in
  json)
    echo "$out"
    ;;
  markdown)
    # markdown 表格 (列 = 结果字段, 含表头分隔行); 空结果无输出
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-rows
    ;;
  *)
    if [[ $header -eq 1 ]]; then
      echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" sql-rows header
    else
      echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" sql-rows
    fi
    ;;
  esac
}

# ---------------------------------------------------------------------------
# raw <args...> — 透传内核 (默认 table 格式, 不加 -f); 退出码/错误原样透传
#   --markdown 被吞掉: raw 输出本就是原样, 无 markdown 转换 (接受标志避免透传报错)
# raw-help <sub...> — 查底层命令帮助
# ---------------------------------------------------------------------------
cmd_raw() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --markdown)
      shift # 原样透传, 无转换
      ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  sy_kernel ${args[@]+"${args[@]}"} # 空数组兼容 bash 3.2 set -u
}

cmd_raw_help() {
  local rc=0
  sy_kernel "$@" --help || rc=$?
  return "$rc"
}

# ---------------------------------------------------------------------------
# children <block-id> — 子块列表 (编辑前定位): id<TAB>type<TAB>content
# ---------------------------------------------------------------------------
cmd_children() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage children
      return 0
      ;;
    -*) sy_die 2 "children: 未知参数 '$1'" "用法: siyuan children <block|doc> [--json|--markdown]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "children: 缺少块/文档引用" "用法: siyuan children <block|doc> [--json|--markdown] (文档引用自动定位到其根块)"
  local bid
  bid="$(sy_resolve_block children "${args[0]}")" || return $?
  local out
  out="$(sy_json children block children --id "$bid")" || return $?
  case "$SY_MODE" in
  json)
    echo "$out"
    ;;
  markdown)
    # 嵌套列表: `type` 内容片段 + 块链接
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-children
    ;;
  *)
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" children-rows
    ;;
  esac
}

# ---------------------------------------------------------------------------
# backlinks <block-id> [--keyword <kw>] — 反链
# ---------------------------------------------------------------------------
cmd_backlinks() {
  local kw=""
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    --keyword | -k)
      kw="${2:?}"
      shift 2
      ;;
    -h | --help)
      sy_usage backlinks
      return 0
      ;;
    -*) sy_die 2 "backlinks: 未知参数 '$1'" "用法: siyuan backlinks <block|doc> [--keyword <kw>] [--json|--markdown]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "backlinks: 缺少块/文档引用" "用法: siyuan backlinks <block|doc> [--keyword <kw>] [--json|--markdown] (文档引用自动定位到其根块)"
  local bid
  bid="$(sy_resolve_block backlinks "${args[0]}")" || return $?
  local bargs=(ref backlinks --id "$bid")
  [[ -n "$kw" ]] && bargs+=(--keyword "$kw")
  # 内核 backlinks 在 JSON 后附加 "N backlink(s)" 摘要文本, 需提取 JSON 部分
  local raw rc=0
  raw="$(sy_kernel -f "${bargs[@]}")" || rc=$?
  [[ $rc -eq 0 ]] || return "$rc"
  local out
  out="$(printf '%s' "$raw" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" extract-json)" || return $?
  case "$SY_MODE" in
  json)
    echo "$out"
    ;;
  markdown)
    # 递归嵌套列表 (内容 + 块链接)
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-backlinks
    ;;
  *)
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" backlinks-rows
    ;;
  esac
}
