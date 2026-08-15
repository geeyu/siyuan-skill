#!/usr/bin/env bash
# siyuan 查询命令组: ls / tree / cat / head / tail / find / grep / which / stat
# 命名与参数参考 Linux 同名命令, 语义映射到思源笔记; 输出行式可组合, --json 稳定字段

# ---------------------------------------------------------------------------
# ls [笔记本] [路径] [-l] [--json]
#   无参: 列笔记本 (SIYUAN_DEFAULT_NOTEBOOK 已设时列该库根目录文档)
#   ls <笔记本> [路径]: 列文档; 路径支持 hpath(/供应链) 或 internal path(/2024xxx.sy)
#   输出: 文本 id<TAB>名称 (加 -l 附 子文档数/大小/修改时间); --json 稳定字段
# ---------------------------------------------------------------------------
cmd_ls() {
  local json=$SY_JSON_DEFAULT long=0
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json)
      json=1
      shift
      ;;
    -l)
      long=1
      shift
      ;;
    -h | --help)
      sy_usage ls
      return 0
      ;;
    -*) sy_die 2 "ls: 未知参数 '$1'" "用法: siyuan ls [笔记本] [路径] [-l] [--json]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  local nb="${args[0]:-}" pth="${args[1]:-}"
  # 设了默认笔记本时, 无参 ls 列该库文档; 首个参数为 /路径 视为路径
  if [[ -n "$SIYUAN_DEFAULT_NOTEBOOK" && -z "$nb" ]]; then
    nb="$SIYUAN_DEFAULT_NOTEBOOK"
  elif [[ -n "$SIYUAN_DEFAULT_NOTEBOOK" && -z "${args[1]:-}" && "$nb" == /* ]]; then
    pth="$nb"
    nb="$SIYUAN_DEFAULT_NOTEBOOK"
  fi

  if [[ -z "$nb" ]]; then
    # --- 列笔记本 ---
    local out
    out="$(sy_json ls notebook list)" || return $?
    if [[ $json -eq 1 ]]; then
      echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" pick id name icon closed sort
    elif [[ $long -eq 1 ]]; then
      echo "$out" | sy_tsv id name closed
    else
      echo "$out" | sy_tsv id name
    fi
    return 0
  fi

  # --- 列笔记本下文档 ---
  local nbid
  nbid="$(sy_resolve_notebook ls "$nb")" || return $?
  local out dargs=(document list --notebook "$nbid")
  if [[ -n "$pth" ]]; then
    # internal path 形如 /20241206xxxx-abc.sy...; 其余按人类可读 hpath
    if [[ "$pth" =~ ^/[0-9]{14}-[a-z0-9]{6,8}(/|$) ]]; then
      dargs+=(--path "$pth")
    else
      dargs+=(--hpath "$pth")
    fi
  fi
  out="$(sy_json ls "${dargs[@]}")" || return $?
  if [[ $json -eq 1 ]]; then
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" pick id name path size subFileCount mtime
  elif [[ $long -eq 1 ]]; then
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" ls-doc-long
  else
    echo "$out" | sy_tsv id name
  fi
}

# ---------------------------------------------------------------------------
# tree <doc> [-l] [--json]
#   标题树/大纲 (对应 outline get); 文本按标题层级缩进, -l 附块 id
# ---------------------------------------------------------------------------
cmd_tree() {
  local json=$SY_JSON_DEFAULT long=0
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json)
      json=1
      shift
      ;;
    -l)
      long=1
      shift
      ;;
    -h | --help)
      sy_usage tree
      return 0
      ;;
    -*) sy_die 2 "tree: 未知参数 '$1'" "用法: siyuan tree <doc> [-l] [--json]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "tree: 缺少文档参数" "用法: siyuan tree <doc-id|标题|/路径> [-l] [--json]"
  local doc
  doc="$(sy_resolve_doc tree "${args[0]}")" || return $?
  local out
  out="$(sy_json tree outline get --id "$doc")" || return $?
  if [[ $json -eq 1 ]]; then
    echo "$out"
  elif [[ $long -eq 1 ]]; then
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" tree-rows long
  else
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" tree-rows
  fi
}

# ---------------------------------------------------------------------------
# cat <doc> [--json]
#   读文档 markdown (对应 export md, 最准); 文本=纯 markdown, 可管道消费
# ---------------------------------------------------------------------------
cmd_cat() {
  local json=$SY_JSON_DEFAULT
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json)
      json=1
      shift
      ;;
    -h | --help)
      sy_usage cat
      return 0
      ;;
    -*) sy_die 2 "cat: 未知参数 '$1'" "用法: siyuan cat <doc-id|标题|/路径> [--json]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "cat: 缺少文档参数" "用法: siyuan cat <doc-id|标题|/路径> [--json]"
  local doc
  doc="$(sy_resolve_doc cat "${args[0]}")" || return $?

  if [[ $json -eq 1 ]]; then
    local md rc=0
    md="$(sy_kernel export md --id "$doc")" || rc=$?
    [[ $rc -eq 0 ]] || sy_die 1 "cat: 读取文档失败" "运行 'siyuan stat ${args[0]}' 确认文档存在"
    local meta
    meta="$(sy_doc_meta cat "$doc")"
    local hpath box
    hpath="${meta%%$'\t'*}"
    box="${meta#*$'\t'}"
    printf '%s' "$md" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" cat-json "$doc" "$hpath" "$box"
  else
    local rc=0
    sy_kernel export md --id "$doc" || rc=$?
    [[ $rc -eq 0 ]] || return "$rc"
  fi
}

# ---------------------------------------------------------------------------
# head / tail <doc> [-n N] [--json]   (默认 10 行, 内部 cat 截断, 不新增内核调用)
# ---------------------------------------------------------------------------
sy_head_tail() {
  local mode="$1"
  shift
  local n=10 json=$SY_JSON_DEFAULT
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -n | --lines)
      n="${2:?}"
      shift 2
      ;;
    -n[0-9]*)
      n="${1#-n}"
      shift
      ;;
    --json)
      json=1
      shift
      ;;
    -h | --help)
      sy_usage "$mode"
      return 0
      ;;
    -*) sy_die 2 "$mode: 未知参数 '$1'" "用法: siyuan $mode <doc> [-n N] [--json]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "$mode: 缺少文档参数" "用法: siyuan $mode <doc-id|标题|/路径> [-n N] [--json]"
  [[ "$n" =~ ^[0-9]+$ ]] || sy_die 2 "$mode: 行数 '$n' 非法" "用法: siyuan $mode <doc> -n N"
  local doc
  doc="$(sy_resolve_doc "$mode" "${args[0]}")" || return $?
  local md rc=0
  md="$(sy_kernel export md --id "$doc")" || rc=$?
  [[ $rc -eq 0 ]] || sy_die 1 "$mode: 读取文档失败" "运行 'siyuan stat ${args[0]}' 确认文档存在"
  local body
  if [[ "$mode" == "head" ]]; then
    body="$(head -n "$n" <<<"$md")"
  else
    body="$(tail -n "$n" <<<"$md")"
  fi
  if [[ $json -eq 1 ]]; then
    printf '%s' "$body" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" head-json "$doc" "$mode" "$n"
  else
    printf '%s\n' "$body"
  fi
}
cmd_head() { sy_head_tail head "$@"; }
cmd_tail() { sy_head_tail tail "$@"; }

# ---------------------------------------------------------------------------
# find <关键词> [--notebook <nb>] [-l N] [--json]
#   跨库搜文档标题 (对应 document search); 与 grep 区分: find 找文档, grep 找内容
#   输出: 文本 doc_id<TAB>hPath<TAB>notebook_id
# ---------------------------------------------------------------------------
cmd_find() {
  local json=$SY_JSON_DEFAULT nb="" limit=""
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json)
      json=1
      shift
      ;;
    --notebook | -n)
      nb="${2:?}"
      shift 2
      ;;
    -l | --limit)
      limit="${2:?}"
      shift 2
      ;;
    -h | --help)
      sy_usage find
      return 0
      ;;
    -*) sy_die 2 "find: 未知参数 '$1'" "用法: siyuan find <关键词> [--notebook <nb>] [-l N] [--json]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "find: 缺少关键词" "用法: siyuan find <关键词> [--notebook <nb>] [--json]"
  local kw="${args[0]}"
  local nbid=""
  if [[ -n "$nb" ]]; then
    nbid="$(sy_resolve_notebook find "$nb")" || return $?
  fi
  local out rows
  out="$(sy_json find document search "$kw")" || return $?
  rows="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" docs-search 0 "${nbid:-}" "${limit:-}" "$kw")"
  if [[ $json -eq 1 ]]; then
    echo "$rows"
  else
    echo "$rows" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" tsv id hPath box
  fi
}

# ---------------------------------------------------------------------------
# grep <pattern> [-v] [-i] [-l] [-m 方法] [--notebook <nb>] [--json]
#   双模式:
#     stdin 非终端 -> 行过滤器 (真 grep 语义, 过滤上游输出, 如 siyuan ls 工作 | siyuan grep 调课)
#     stdin 终端   -> 内容全文检索 (kernel search; -m 0=关键词 1=query-syntax 2=sql 3=regex)
#   内容模式输出: doc_id<TAB>hPath<TAB>内容 (-l 只列 doc_id, --json 稳定字段)
# ---------------------------------------------------------------------------
cmd_grep() {
  local json=$SY_JSON_DEFAULT invert=0 ignore=0 listonly=0 method="" nb="" pagesize=32 content=0
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -v)
      invert=1
      shift
      ;;
    -i)
      ignore=1
      shift
      ;;
    -l)
      listonly=1
      shift
      ;;
    -m | --method)
      method="${2:?}"
      shift 2
      ;;
    -n | --notebook)
      nb="${2:?}"
      shift 2
      ;;
    -s | --page-size)
      pagesize="${2:?}"
      shift 2
      ;;
    --content)
      content=1
      shift
      ;;
    --json)
      json=1
      shift
      ;;
    -h | --help)
      sy_usage grep
      return 0
      ;;
    -*) sy_die 2 "grep: 未知参数 '$1'" "用法: siyuan grep <pattern> [-v] [-i] [-l] [-m 0-3] [--notebook <nb>] [--json]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "grep: 缺少 pattern" "用法: siyuan grep <pattern> [...] (管道输入时按行过滤, 终端时内容检索, --content 强制内容检索)"

  # --- 管道模式: 行过滤器 (非终端且未强制内容检索) ---
  if [[ ! -t 0 && $content -eq 0 && -z "$method" ]]; then
    local gargs=(-E)
    [[ $invert -eq 1 ]] && gargs+=(-v)
    [[ $ignore -eq 1 ]] && gargs+=(-i)
    if grep "${gargs[@]}" -- "${args[0]}"; then
      return 0
    else
      return $?
    fi
  fi

  # --- 内容检索模式 ---
  local sargs=(search "${args[0]}" -s "$pagesize")
  [[ -n "$method" ]] && sargs+=(-m "$method")
  if [[ -n "$nb" ]]; then
    local nbid
    nbid="$(sy_resolve_notebook grep "$nb")" || return $?
    sargs+=(-n "$nbid")
  fi
  local out
  out="$(sy_json grep "${sargs[@]}")" || return $?
  local count
  count="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" len-blocks)"
  if [[ "$count" -eq 0 ]]; then
    sy_die 1 "grep: 没有匹配 '${args[0]}' 的块" "换关键词, 或用 -m 3 正则模式检索"
  fi
  if [[ $json -eq 1 ]]; then
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" grep-json
  elif [[ $listonly -eq 1 ]]; then
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" grep-ids
  else
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" grep-tsv
  fi
}

# ---------------------------------------------------------------------------
# which <doc-id|标题|/路径> [-v] [--json]
#   定位文档: 输出唯一 doc id (可组合: cat $(siyuan which 标题))
#   -v 附 hPath/notebook; 多匹配时列出候选并退出 1
# ---------------------------------------------------------------------------
cmd_which() {
  local json=$SY_JSON_DEFAULT verbose=0
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json)
      json=1
      shift
      ;;
    -v)
      verbose=1
      shift
      ;;
    -h | --help)
      sy_usage which
      return 0
      ;;
    -*) sy_die 2 "which: 未知参数 '$1'" "用法: siyuan which <doc-id|标题|/路径> [-v] [--json]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "which: 缺少文档引用" "用法: siyuan which <doc-id|标题|/完整路径> [-v] [--json]"
  local out
  out="$(sy_locate_docs which "${args[0]}")"
  local n
  n="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" len)"
  if [[ "$n" -eq 0 ]]; then
    sy_die 1 "which: 找不到文档 '${args[0]}'" "用 'siyuan find ${args[0]}' 搜相近文档, 或 'siyuan ls' 看笔记本结构"
  fi
  if [[ $json -eq 1 ]]; then
    echo "$out"
  elif [[ $verbose -eq 1 ]]; then
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" tsv id hPath box
  else
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" ids
  fi
  if [[ "$n" -gt 1 ]]; then
    sy_die 1 "which: 存在 $n 个匹配" "用完整路径消歧, 如 'siyuan which /完整/路径/标题'; 或 -v 看全部候选"
  fi
}

# ---------------------------------------------------------------------------
# stat <doc> [--json]
#   文档元信息 (对应 document get); 文本 key: value, --json 原始对象
# ---------------------------------------------------------------------------
cmd_stat() {
  local json=$SY_JSON_DEFAULT
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json)
      json=1
      shift
      ;;
    -h | --help)
      sy_usage stat
      return 0
      ;;
    -*) sy_die 2 "stat: 未知参数 '$1'" "用法: siyuan stat <doc-id|标题|/路径> [--json]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "stat: 缺少文档参数" "用法: siyuan stat <doc-id|标题|/路径> [--json]"
  local doc
  doc="$(sy_resolve_doc stat "${args[0]}")" || return $?
  local out
  out="$(sy_json stat document get --id "$doc")" || return $?
  if [[ $json -eq 1 ]]; then
    echo "$out"
  else
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" stat-text
  fi
}
