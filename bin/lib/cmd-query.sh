#!/usr/bin/env bash
# siyuan 查询命令组: ls / tree / cat / head / tail / find / grep / which / stat
# 命名与参数参考 Linux 同名命令, 语义映射到思源笔记; 输出行式可组合,
# --json 稳定字段 / --markdown 笔记可直接用 (框架统一路由, 与 --json 互斥)

# ---------------------------------------------------------------------------
# ls [笔记本] [路径] [-l] [--json]
#   无参: 列笔记本 (SIYUAN_DEFAULT_NOTEBOOK 已设时列该库根目录文档)
#   ls <笔记本> [路径]: 列文档; 路径支持 hpath(/供应链) 或 internal path(/2024xxx.sy)
#   输出: 文本 id<TAB>名称 (加 -l 附 子文档数/大小/修改时间); --json 稳定字段
# ---------------------------------------------------------------------------
cmd_ls() {
  local long=0
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
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
    -*) sy_die 2 "ls: 未知参数 '$1'" "用法: siyuan ls [引用] [-l] [--json|--markdown]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  local ref="${args[0]:-}" pth="${args[1]:-}"

  # 无参: 列笔记本 (SIYUAN_DEFAULT_NOTEBOOK 已设时列该库根)
  if [[ -z "$ref" ]]; then
    if [[ -n "$SIYUAN_DEFAULT_NOTEBOOK" ]]; then
      ref="$SIYUAN_DEFAULT_NOTEBOOK"
    else
      local out
      out="$(sy_json ls notebook list)" || return $?
      case "$SY_MODE" in
      json)
        echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" pick id name icon closed sort
        ;;
      markdown)
        local mtargs=(名称:name ID:id)
        [[ $long -eq 1 ]] && mtargs+=(关闭:closed)
        echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-table "${mtargs[@]}"
        ;;
      *)
        if [[ $long -eq 1 ]]; then
          echo "$out" | sy_tsv id name closed
        else
          echo "$out" | sy_tsv id name
        fi
        ;;
      esac
      return 0
    fi
  fi

  local nbid="" doc_id="" pure_hpath=""
  local nbsoft
  # 引用解析: 先试笔记本 (名/id); 单参是笔记本 → 列库根
  nbsoft="$(sy_resolve_notebook_soft ls "$ref")" || return $?
  if [[ -n "$nbsoft" && -z "$pth" ]]; then
    nbid="$nbsoft"
  else
    # 文档引用定位 (单参: id/标题/路径; 双参兼容: 笔记本 + 路径, 拼合定位)
    local target="$ref"
    [[ -n "$pth" ]] && target="${ref%/}${pth}"
    local out
    out="$(sy_locate_docs ls "$target")"
    local n
    n="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" len)"
    if [[ "$n" -eq 0 ]]; then
      sy_die 1 "ls: 找不到 '$target'" "路径必须完整存在 (模糊用显式通配, 如 'siyuan ls /*/调课'); 或 'siyuan find $target' 搜标题"
    fi
    # glob 显式通配: 多命中列出文档本身 (Linux 通配展开语义, 非歧义)
    if [[ "$n" -gt 1 && "$target" == *\** || "$n" -gt 1 && "$target" == *\?* ]]; then
      local idlist
      idlist="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" ids | sed "s/.*/'&'/" | paste -sd, -)"
      local dout
      dout="$(sy_json ls sql "SELECT id, content AS name, path, 0 AS size, 0 AS subFileCount, updated AS mtime, box FROM blocks WHERE id IN ($idlist) ORDER BY hpath")" || return $?
      case "$SY_MODE" in
      json)
        echo "$dout" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" pick id name path size subFileCount mtime
        ;;
      markdown)
        local nbname
        nbname="$(sy_nb_name ls "$nbid")" || return $?
        echo "$dout" | NB_NAME="$nbname" "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ls-docs
        ;;
      *)
        if [[ $long -eq 1 ]]; then
          echo "$dout" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" ls-doc-long
        else
          echo "$dout" | sy_tsv id name
        fi
        ;;
      esac
      return 0
    fi
    if [[ "$n" -gt 1 ]]; then
      local names
      names="$(sy_nb_names ls)" || return $?
      echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" candidates >&2
      sy_die 1 "ls: '$target' 有 $n 个匹配" "用完整路径消歧, 如 'siyuan ls /工作/完整/路径'"
    fi
    doc_id="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" ids)"
    nbid="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" tsv box)"
    # 纯 hpath (document list --hpath 需要, 不含笔记本名)
    pure_hpath="$(sy_json ls sql "SELECT hpath FROM blocks WHERE id='$doc_id'" |
      "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field hpath)" || return $?
  fi

  # --- 列文档 ---
  local out dargs=(document list --notebook "$nbid")
  if [[ -n "$doc_id" ]]; then
    # internal path (底层细节, 兼容): /2024xxx.sy...
    if [[ "${args[0]:-}" =~ ^/[0-9]{14}-[a-z0-9]{6,8}(/|$) ]] || [[ "${args[1]:-}" =~ ^/[0-9]{14}-[a-z0-9]{6,8}(/|$) ]]; then
      dargs+=(--path "${args[1]:-${args[0]}}")
    else
      # 子文档数: 0 则显示文档本身 (Linux ls 文件语义, 区分「存在但空」与「不存在」)
      local esc
      esc="${pure_hpath//\'/\'\'}"
      local sub
      sub="$(sy_json ls sql "SELECT count(*) AS cnt FROM blocks WHERE hpath LIKE '${esc}/%' AND type='d'" |
        "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field cnt)" || return $?
      if [[ "$sub" == "0" ]]; then
        local dout
        dout="$(sy_json ls sql "SELECT id, content AS name, path, 0 AS size, 0 AS subFileCount, updated AS mtime, box FROM blocks WHERE id='$doc_id'")" || return $?
        case "$SY_MODE" in
        json)
          echo "$dout" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" pick id name path size subFileCount mtime
          ;;
        markdown)
          local nbname
          nbname="$(sy_nb_name ls "$nbid")" || return $?
          echo "$dout" | NB_NAME="$nbname" "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ls-docs
          ;;
        *)
          if [[ $long -eq 1 ]]; then
            echo "$dout" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" ls-doc-long
          else
            echo "$dout" | sy_tsv id name
          fi
          ;;
        esac
        return 0
      fi
      dargs+=(--hpath "$pure_hpath")
    fi
  fi
  out="$(sy_json ls "${dargs[@]}")" || return $?
  case "$SY_MODE" in
  json)
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" pick id name path size subFileCount mtime
    ;;
  markdown)
    local nbname
    nbname="$(sy_nb_name ls "$nbid")" || return $?
    if [[ $long -eq 1 ]]; then
      echo "$out" | NB_NAME="$nbname" "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ls-docs long
    else
      echo "$out" | NB_NAME="$nbname" "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ls-docs
    fi
    ;;
  *)
    if [[ $long -eq 1 ]]; then
      echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" ls-doc-long
    else
      echo "$out" | sy_tsv id name
    fi
    ;;
  esac
}

cmd_tree() {
  local long=0
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
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
    -*) sy_die 2 "tree: 未知参数 '$1'" "用法: siyuan tree <doc> [-l] [--json|--markdown]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "tree: 缺少文档参数" "用法: siyuan tree <doc> [-l] [--json|--markdown]"
  local doc
  doc="$(sy_resolve_doc tree "${args[0]}")" || return $?
  # 无标题文档 (目录文档/空文档) 是合法场景: 输出空而非内核报错
  local hcnt
  hcnt="$(sy_json tree sql "SELECT count(*) AS cnt FROM blocks WHERE root_id='$doc' AND type='h'" |
    "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field cnt)" || return $?
  if [[ -z "$hcnt" || "$hcnt" == "0" ]]; then
    case "$SY_MODE" in
    json) echo '[]' ;;
    *) : ;;
    esac
    return 0
  fi
  local out
  out="$(sy_json tree outline get --id "$doc")" || return $?
  case "$SY_MODE" in
  json)
    echo "$out"
    ;;
  markdown)
    local targs=(short) # 占位避免 bash 3.2 set -u 对空数组报错
    [[ $long -eq 1 ]] && targs=(long)
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" tree-md "${targs[@]}"
    ;;
  *)
    if [[ $long -eq 1 ]]; then
      echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" tree-rows long
    else
      echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" tree-rows
    fi
    ;;
  esac
}

# ---------------------------------------------------------------------------
# cat <doc> [--json]
#   读文档 markdown (对应 export md, 最准); 文本=纯 markdown, 可管道消费
# ---------------------------------------------------------------------------
cmd_cat() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage cat
      return 0
      ;;
    -*) sy_die 2 "cat: 未知参数 '$1'" "用法: siyuan cat <doc-id|标题|/路径> [--json|--markdown]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "cat: 缺少文档参数" "用法: siyuan cat <doc-id|标题|/路径> [--json|--markdown]"
  local doc
  doc="$(sy_resolve_doc cat "${args[0]}")" || return $?

  if [[ "$SY_MODE" == "json" ]]; then
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
    # 文本与 --markdown 均为文档 markdown 原样 (cat 输出本就是 md)
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
  local n=10
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
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage "$mode"
      return 0
      ;;
    -*) sy_die 2 "$mode: 未知参数 '$1'" "用法: siyuan $mode <doc> [-n N] [--json|--markdown]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "$mode: 缺少文档参数" "用法: siyuan $mode <doc-id|标题|/路径> [-n N] [--json|--markdown]"
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
  case "$SY_MODE" in
  json)
    printf '%s' "$body" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" head-json "$doc" "$mode" "$n"
    ;;
  markdown)
    # 片段用 fenced code block 标记 (避免与整篇 cat 混淆)
    printf '%s' "$body" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-fence markdown
    ;;
  *)
    printf '%s\n' "$body"
    ;;
  esac
}
cmd_head() { sy_head_tail head "$@"; }
cmd_tail() { sy_head_tail tail "$@"; }

# ---------------------------------------------------------------------------
# find <关键词> [--notebook <nb>] [-l N] [--json]
#   跨库搜文档标题 (对应 document search); 与 grep 区分: find 找文档, grep 找内容
#   输出: 文本 doc_id<TAB>hPath<TAB>notebook_id
# ---------------------------------------------------------------------------
cmd_find() {
  local nb="" limit=""
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
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
    -*) sy_die 2 "find: 未知参数 '$1'" "用法: siyuan find <关键词> [--notebook <nb>] [-l N] [--json|--markdown]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "find: 缺少关键词" "用法: siyuan find <关键词> [--notebook <nb>] [--json|--markdown]"
  local kw="${args[0]}"
  local nbid=""
  if [[ -n "$nb" ]]; then
    nbid="$(sy_resolve_notebook find "$nb")" || return $?
  fi
  local out rows
  out="$(sy_json find document search "$kw")" || return $?
  rows="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" docs-search 0 "${nbid:-}" "${limit:-}" "$kw")"
  case "$SY_MODE" in
  json)
    echo "$rows"
    ;;
  markdown)
    # 列表: [标题](siyuan://docs/<id>) + hpath + 笔记本名
    local names
    names="$(sy_nb_names find)" || return $?
    echo "$rows" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-docs
    ;;
  *)
    local names
    names="$(sy_nb_names find)" || return $?
    echo "$rows" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" tsv id hPath box
    ;;
  esac
}

# ---------------------------------------------------------------------------
# grep <pattern> [-v] [-i] [-l] [-m 方法] [--notebook <nb>] [--json]
#   双模式:
#     stdin 非终端 -> 行过滤器 (真 grep 语义, 过滤上游输出, 如 siyuan ls 工作 | siyuan grep 调课)
#     stdin 终端   -> 内容全文检索 (kernel search; -m 0=关键词 1=query-syntax 2=sql 3=regex)
#   内容模式输出: doc_id<TAB>hPath<TAB>内容 (-l 只列 doc_id, --json 稳定字段)
# ---------------------------------------------------------------------------
cmd_grep() {
  local invert=0 ignore=0 listonly=0 method="" nb="" pagesize=32 content=0
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
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage grep
      return 0
      ;;
    -*) sy_die 2 "grep: 未知参数 '$1'" "用法: siyuan grep <pattern> [-v] [-i] [-l] [-m 0-3] [--notebook <nb>] [--json|--markdown]" ;;
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
  case "$SY_MODE" in
  json)
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" grep-json
    ;;
  markdown)
    # 列表: 按文档分组, 文档 bullet + 内容片段嵌套 bullet
    local names
    names="$(sy_nb_names grep)" || return $?
    if [[ $listonly -eq 1 ]]; then
      echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-grep listonly
    else
      echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-grep
    fi
    ;;
  *)
    if [[ $listonly -eq 1 ]]; then
      echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" grep-ids
    else
      # 文本输出带笔记本名完整路径 (与 find 一致, 可直接喂 which)
      local names
      names="$(sy_nb_names grep)" || return $?
      echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" grep-tsv
    fi
    ;;
  esac
}

# ---------------------------------------------------------------------------
# which <doc-id|标题|/路径> [-v] [--json]
#   定位文档: 输出唯一 doc id (可组合: cat $(siyuan which 标题))
#   -v 附 hPath/notebook; 多匹配时列出候选并退出 1
# ---------------------------------------------------------------------------
cmd_which() {
  local verbose=0
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
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
    -*) sy_die 2 "which: 未知参数 '$1'" "用法: siyuan which <doc-id|标题|/路径> [-v] [--json|--markdown]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "which: 缺少文档引用" "用法: siyuan which <doc-id|标题|/完整路径> [-v] [--json|--markdown]"
  local out
  out="$(sy_locate_docs which "${args[0]}")"
  local n
  n="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" len)"
  if [[ "$n" -eq 0 ]]; then
    sy_die 1 "which: 找不到文档 '${args[0]}'" "用 'siyuan find ${args[0]}' 搜相近文档, 或 'siyuan ls' 看笔记本结构"
  fi
  case "$SY_MODE" in
  json)
    echo "$out"
    ;;
  markdown)
    # 键值列表: 文档 ID / 路径 / 笔记本 (多匹配时同样列出, 错误仍走 stderr)
    local names
    names="$(sy_nb_names which)" || return $?
    echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-kv-list '文档 ID:id' '路径:hPath' '笔记本:boxName'
    ;;
  *)
    if [[ $verbose -eq 1 ]]; then
      local names
      names="$(sy_nb_names which)" || return $?
      echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" tsv id hPath box
    else
      echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" ids
    fi
    ;;
  esac
  if [[ "$n" -gt 1 ]]; then
    sy_die 1 "which: 存在 $n 个匹配" "用完整路径消歧, 如 'siyuan which /完整/路径/标题'; 或 -v 看全部候选"
  fi
}

# ---------------------------------------------------------------------------
# stat <doc> [--json]
#   文档元信息 (对应 document get); 文本 key: value, --json 原始对象
# ---------------------------------------------------------------------------
cmd_stat() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage stat
      return 0
      ;;
    -*) sy_die 2 "stat: 未知参数 '$1'" "用法: siyuan stat <doc-id|标题|/路径> [--json|--markdown]" ;;
    *)
      args+=("$1")
      shift
      ;;
    esac
  done
  [[ -n "${args[0]:-}" ]] || sy_die 2 "stat: 缺少文档参数" "用法: siyuan stat <doc-id|标题|/路径> [--json|--markdown]"
  local doc
  doc="$(sy_resolve_doc stat "${args[0]}")" || return $?
  local out
  out="$(sy_json stat document get --id "$doc")" || return $?
  case "$SY_MODE" in
  json)
    echo "$out"
    ;;
  markdown)
    # 键值表格: 字段 | 值
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-keyval
    ;;
  *)
    echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" stat-text
    ;;
  esac
}
