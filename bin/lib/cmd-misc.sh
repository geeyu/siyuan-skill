#!/usr/bin/env bash
# siyuan 其他命令: sql / raw / raw-help / children / backlinks

# ---------------------------------------------------------------------------
# sql "<语句>" [-l N] [--json]
#   SQL 查询 (透传内核 sql, 默认 limit 100); 文本=TSV 行 (无表头, 可组合)
# ---------------------------------------------------------------------------
cmd_sql() {
  local json=$SY_JSON_DEFAULT limit=100 header=0
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json)
      json=1
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
    -*) sy_die 2 "sql: 未知参数 '$1'" "用法: siyuan sql \"<语句>\" [-l N] [-H] [--json]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "sql: 缺少 SQL 语句" "用法: siyuan sql \"<statement>\" [-l N] [--json] (例: siyuan sql \"SELECT id,hpath FROM blocks WHERE type='d' LIMIT 5\")"
  local stmt="${args[0]}"
  local out
  out="$(sy_json sql sql "$stmt" -l "$limit")" || return $?
  if [[ $json -eq 1 ]]; then
    echo "$out"
  elif [[ $header -eq 1 ]]; then
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" sql-rows header
  else
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" sql-rows
  fi
}

# ---------------------------------------------------------------------------
# raw <args...> — 透传内核 (默认 table 格式, 不加 -f); 退出码/错误原样透传
# raw-help <sub...> — 查底层命令帮助
# ---------------------------------------------------------------------------
cmd_raw() {
  sy_kernel "$@"
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
  local json=$SY_JSON_DEFAULT
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json)
      json=1
      shift
      ;;
    -h | --help)
      sy_usage children
      return 0
      ;;
    -*) sy_die 2 "children: 未知参数 '$1'" "用法: siyuan children <block-id> [--json]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "children: 缺少块 id" "用法: siyuan children <block-id> [--json]"
  local out
  out="$(sy_json children block children --id "${args[0]}")" || return $?
  if [[ $json -eq 1 ]]; then
    echo "$out"
  else
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" children-rows
  fi
}

# ---------------------------------------------------------------------------
# backlinks <block-id> [--keyword <kw>] — 反链
# ---------------------------------------------------------------------------
cmd_backlinks() {
  local json=$SY_JSON_DEFAULT kw=""
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json)
      json=1
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
    -*) sy_die 2 "backlinks: 未知参数 '$1'" "用法: siyuan backlinks <block-id> [--keyword <kw>] [--json]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "backlinks: 缺少块 id" "用法: siyuan backlinks <block-id> [--keyword <kw>] [--json]"
  local bargs=(ref backlinks --id "${args[0]}")
  [[ -n "$kw" ]] && bargs+=(--keyword "$kw")
  # 内核 backlinks 在 JSON 后附加 "N backlink(s)" 摘要文本, 需提取 JSON 部分
  local raw rc=0
  raw="$(sy_kernel -f "${bargs[@]}")" || rc=$?
  [[ $rc -eq 0 ]] || return "$rc"
  local out
  out="$(printf '%s' "$raw" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" extract-json)" || return $?
  if [[ $json -eq 1 ]]; then
    echo "$out"
  else
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" backlinks-rows
  fi
}
