#!/usr/bin/env bash
# siyuan 编辑命令组 (shell 风格): touch / edit / mv / cp / rm / diff / rename
# 命名与参数参考 Linux 同名命令, 语义映射到思源笔记:
#   touch  = 新建文档 (createDocWithMd 三步语义, HTTP 不可用回退 CLI)
#   edit   = 统一编辑入口 (内部路由 append/prepend/update-block/replace-doc)
#   mv     = 移动文档 (同/跨笔记本, 封装层语义)
#   cp     = 复制文档 (duplicate)
#   rm     = 删除文档 (接受 id/标题/路径引用)
#   diff   = 对比两文档 markdown (内部 cat + diff, 统一 diff 格式)
#   rename = 重命名 (IAL title + H1 同步, 避免 title/H1 不一致)
# 硬约束: 每次写操作返回目标 id; 内容走 argv/stdin/文件 (无 shell 拼接注入)

# ---------------------------------------------------------------------------
# 共享: 解析内容 (mode_arg / --file / stdin 优先级递减)
#   sy_edit_data <ctx> <mode_arg> <file> -> stdout: 内容; 空则 sy_die 2
# ---------------------------------------------------------------------------
sy_edit_data() {
  local ctx="$1" data="$2" file="$3"
  if [[ -z "$data" && -n "$file" ]]; then data="$(cat "$file")"; fi
  if [[ -z "$data" && ! -t 0 ]]; then data="$(cat)"; fi
  if [[ -z "$data" ]]; then
    sy_die 2 "$ctx: 没有提供内容" "在模式参数后跟文本, 或用 --file <文件> / 管道 stdin 传入"
  fi
  printf '%s' "$data"
}

# ---------------------------------------------------------------------------
# touch --notebook <nb> --title <t> [--parent <pid>] [--path <hpath>] [--file <f>|stdin]
#   新建文档 (默认笔记本根目录; 内容可选, 空文档=空文件语义)
#   返回: 新文档 id
# ---------------------------------------------------------------------------
cmd_touch() {
  local nb="" title="" parent_id="" hpath="" file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --notebook | -n)
      nb="${2:?}"
      shift 2
      ;;
    --title | -t)
      title="${2:?}"
      shift 2
      ;;
    --parent)
      parent_id="${2:?}"
      shift 2
      ;;
    --path | -p)
      hpath="${2:?}"
      shift 2
      ;;
    --file | -f)
      file="${2:?}"
      shift 2
      ;;
    -h | --help)
      sy_usage touch
      return 0
      ;;
    *) sy_die 2 "touch: 未知参数 '$1'" "用法: siyuan touch --notebook <nb> --title <t> [--parent <pid> | --path <hpath>] [--file <md>|stdin]" ;;
    esac
  done
  if [[ -z "$nb" || -z "$title" ]]; then
    sy_die 2 "touch: 缺少 --notebook 或 --title" "用法: siyuan touch --notebook <nb> --title <t> [--parent <pid> | --path <hpath>] [--file <md>|stdin]"
  fi
  local nbid
  nbid="$(sy_resolve_notebook touch "$nb")" || return $?

  local md=""
  if [[ -n "$file" ]]; then
    md="$(cat "$file")"
  elif [[ ! -t 0 ]]; then
    md="$(cat)"
  fi

  sy_doc_create touch "$nbid" "$title" "$parent_id" "$hpath" "$md" || return $?
}

# ---------------------------------------------------------------------------
# edit <doc> [--append <text>|--prepend <text>|--update <block-id> <text>|--replace <text>]
#   [--file <f>|stdin 提供文本]
#   统一编辑入口, 内部路由:
#     --append   -> block append    (追加到文档末尾)
#     --prepend  -> block prepend   (插入到文档开头)
#     --update   -> block update    (改指定块内容)
#     --replace  -> replace-doc 语义 (删旧写新, 保留标题)
#   返回: 目标 id (append/prepend/replace = 文档 id, update = 块 id)
# ---------------------------------------------------------------------------
cmd_edit() {
  local doc_ref="${1:-}"
  [[ -n "$doc_ref" ]] || sy_die 2 "edit: 缺少文档参数" "用法: siyuan edit <doc> [--append <text>|--prepend <text>|--update <block-id> <text>|--replace <text>] [--file <f>|stdin]"
  shift
  local mode="" mode_arg="" block_id="" file=""
  # 判断下一个参数是否是命令自身的已知 flag (非已知 flag 一律视为文本参数, 支持 "- 列表项" 这类内容)
  sy_is_edit_flag() {
    case "$1" in
    --append | --prepend | --update | --replace | --file | -f | -h | --help) return 0 ;;
    *) return 1 ;;
    esac
  }
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --append | --prepend | --replace)
      mode="${1#--}"
      # 可选紧跟文本参数 (下一个参数不是命令 flag 即为文本)
      if [[ $# -ge 2 ]] && ! sy_is_edit_flag "$2"; then
        mode_arg="$2"
        shift 2
      else
        shift
      fi
      ;;
    --update)
      mode="update"
      if [[ $# -ge 2 ]] && ! sy_is_edit_flag "$2"; then
        block_id="$2"
        shift 2
        # 紧跟的可选文本参数 (--update <block-id> <text>)
        if [[ $# -ge 1 ]] && ! sy_is_edit_flag "$1"; then
          mode_arg="$1"
          shift
        fi
      else
        shift
      fi
      ;;
    --file | -f)
      file="${2:?}"
      shift 2
      ;;
    -h | --help)
      sy_usage edit
      return 0
      ;;
    *) sy_die 2 "edit: 未知参数 '$1'" "用法: siyuan edit <doc> [--append <text>|--prepend <text>|--update <block-id> <text>|--replace <text>] [--file <f>|stdin]" ;;
    esac
  done
  [[ -n "$mode" ]] || sy_die 2 "edit: 缺少编辑模式" "用法: siyuan edit <doc> [--append <text>|--prepend <text>|--update <block-id> <text>|--replace <text>]"
  if [[ "$mode" == "update" ]]; then
    [[ -n "$block_id" ]] || sy_die 2 "edit: --update 缺少块 id" "用法: siyuan edit <doc> --update <block-id> <text> (块 id 用 'siyuan children <doc>' 定位)"
  fi

  local doc
  doc="$(sy_resolve_doc edit "$doc_ref")" || return $?
  local data
  data="$(sy_edit_data edit "$mode_arg" "$file")"

  case "$mode" in
  append)
    sy_kernel_or_die edit block append --parent "$doc" --data "$data" >/dev/null
    echo "$doc"
    ;;
  prepend)
    sy_kernel_or_die edit block prepend --parent "$doc" --data "$data" >/dev/null
    echo "$doc"
    ;;
  update)
    # 校验块存在且属于该文档 (防止改错块)
    local root
    root="$(sy_json edit sql "SELECT root_id FROM blocks WHERE id='$block_id'" |
      "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field root_id)" || return $?
    if [[ -z "$root" ]]; then
      sy_die 1 "edit: 找不到块 '$block_id'" "用 'siyuan children $doc' 查看文档下的块 id"
    fi
    if [[ "$root" != "$doc" ]]; then
      sy_die 1 "edit: 块 '$block_id' 不属于文档 '$doc_ref'" "用 'siyuan children $doc' 查看该文档下的块 id"
    fi
    sy_kernel_or_die edit block update --id "$block_id" --data "$data" >/dev/null
    echo "$block_id"
    ;;
  replace)
    sy_replace_doc edit "$doc" "$data" >/dev/null || return $?
    echo "$doc"
    ;;
  esac
}

# ---------------------------------------------------------------------------
# mv <doc> --to <parent-id> [--notebook <nb>] | mv <doc> --notebook <nb>
#   移动文档 (同/跨笔记本均支持, 底层 CLI document move 同语义)
#   --to <parent-id>     移到该文档下 (父文档 id/标题/路径)
#   --notebook <nb>      显式指定目标笔记本 (无 --to 时移到该库根目录)
#   返回: 被移动的文档 id
# ---------------------------------------------------------------------------
cmd_mv() {
  local doc_ref="${1:-}"
  [[ -n "$doc_ref" ]] || sy_die 2 "mv: 缺少文档参数" "用法: siyuan mv <doc> --to <parent-id> [--notebook <nb>]"
  shift
  local to_ref="" nb_ref=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --to)
      to_ref="${2:?}"
      shift 2
      ;;
    --notebook | -n)
      nb_ref="${2:?}"
      shift 2
      ;;
    -h | --help)
      sy_usage mv
      return 0
      ;;
    *) sy_die 2 "mv: 未知参数 '$1'" "用法: siyuan mv <doc> --to <parent-id> [--notebook <nb>]" ;;
    esac
  done
  [[ -n "$to_ref" || -n "$nb_ref" ]] || sy_die 2 "mv: 缺少 --to 或 --notebook" "用法: siyuan mv <doc> --to <parent-id> [--notebook <nb>]"

  local doc
  doc="$(sy_resolve_doc mv "$doc_ref")" || return $?
  local to_box="" to_path="/"
  if [[ -n "$to_ref" ]]; then
    local parent
    parent="$(sy_resolve_doc mv "$to_ref")" || return $?
    to_path="$(sy_doc_path mv "$parent")" || return $?
    to_box="$(sy_json mv sql "SELECT box FROM blocks WHERE id='$parent'" |
      "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field box)" || return $?
    [[ -n "$to_box" ]] || sy_die 1 "mv: 无法解析父文档 '$to_ref' 的笔记本" "用 'siyuan which $to_ref' 确认父文档存在"
    if [[ -n "$nb_ref" ]]; then
      local nbid
      nbid="$(sy_resolve_notebook mv "$nb_ref")" || return $?
      if [[ "$nbid" != "$to_box" ]]; then
        sy_die 1 "mv: --notebook 与 --to 父文档所在笔记本不一致" "去掉 --notebook (自动取父文档所在库), 或改 --to"
      fi
    fi
  else
    to_box="$(sy_resolve_notebook mv "$nb_ref")" || return $?
  fi

  sy_kernel_or_die mv document move --id "$doc" --notebook "$to_box" --path "$to_path" >/dev/null
  echo "$doc"
}

# ---------------------------------------------------------------------------
# cp <doc> [--to <parent-id>]
#   复制文档 (duplicate, 同目录生成 "标题 (Duplicated ...)" 副本)
#   --to <parent-id>     复制后移到该文档下 (可跨笔记本, 自动取父文档所在库)
#   返回: 新副本的文档 id
# ---------------------------------------------------------------------------
cmd_cp() {
  local doc_ref="${1:-}"
  [[ -n "$doc_ref" ]] || sy_die 2 "cp: 缺少文档参数" "用法: siyuan cp <doc> [--to <parent-id>]"
  shift
  local to_ref=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --to)
      to_ref="${2:?}"
      shift 2
      ;;
    -h | --help)
      sy_usage cp
      return 0
      ;;
    *) sy_die 2 "cp: 未知参数 '$1'" "用法: siyuan cp <doc> [--to <parent-id>]" ;;
    esac
  done

  local doc
  doc="$(sy_resolve_doc cp "$doc_ref")" || return $?
  local new_id rc=0
  # sy_kernel 是裸透传 (不像 sy_kernel_or_die 会剥离上下文前缀), 这里不能带 "cp" 前缀
  new_id="$(sy_kernel document duplicate --id "$doc" 2>/dev/null)" || rc=$?
  if [[ $rc -eq 124 ]]; then
    sy_die 124 "cp: 内核 ${SIYUAN_TIMEOUT} 秒无响应" "重试, 或调大 SIYUAN_TIMEOUT 环境变量"
  elif [[ $rc -ne 0 ]]; then
    sy_die 1 "cp: 复制文档失败 (内核返回 $rc)" "运行 'siyuan raw document duplicate --help' 查看参数"
  fi
  new_id="$(printf '%s\n' "$new_id" | head -1)"
  [[ -n "$new_id" ]] || sy_die 1 "cp: 复制文档失败, 未返回新文档 id" "重试或检查内核输出"

  if [[ -n "$to_ref" ]]; then
    local parent to_path to_box
    parent="$(sy_resolve_doc cp "$to_ref")" || return $?
    to_path="$(sy_doc_path cp "$parent")" || return $?
    to_box="$(sy_json cp sql "SELECT box FROM blocks WHERE id='$parent'" |
      "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field box)" || return $?
    sy_kernel_or_die cp document move --id "$new_id" --notebook "$to_box" --path "$to_path" >/dev/null
  fi
  echo "$new_id"
}

# ---------------------------------------------------------------------------
# rm <doc> — 删除文档 (引用可为 id/标题/路径)
#   返回: 被删除的文档 id
# ---------------------------------------------------------------------------
cmd_rm() {
  local doc_ref="${1:-}"
  [[ -n "$doc_ref" ]] || sy_die 2 "rm: 缺少文档参数" "用法: siyuan rm <doc-id|标题|/路径>"
  local doc
  doc="$(sy_resolve_doc rm "$doc_ref")" || return $?
  sy_doc_delete rm "$doc"
  echo "$doc"
}

# ---------------------------------------------------------------------------
# diff <docA> <docB> [diff 参数...] — 对比两文档 markdown (内部 cat + diff)
#   输出: 统一 diff 格式 (默认 -u); 退出码同 diff: 0=相同 1=有差异
# ---------------------------------------------------------------------------
cmd_diff() {
  local a_ref="${1:-}" b_ref="${2:-}"
  shift 2 2>/dev/null || true
  [[ -n "$a_ref" && -n "$b_ref" ]] || sy_die 2 "diff: 需要两个文档参数" "用法: siyuan diff <docA> <docB> [diff 参数...] (例: siyuan diff A B -w -U 5)"

  local a b
  a="$(sy_resolve_doc diff "$a_ref")" || return $?
  b="$(sy_resolve_doc diff "$b_ref")" || return $?

  local tmpa tmpb
  tmpa="$(mktemp /tmp/siyuan-diff-a.XXXXXX)"
  tmpb="$(mktemp /tmp/siyuan-diff-b.XXXXXX)"
  # 用全局变量承载 trap 引用 (函数 local 在 return 后销毁, trap 里引用会 unbound)
  SY_DIFF_TMP_A="$tmpa"
  SY_DIFF_TMP_B="$tmpb"
  trap 'rm -f "$SY_DIFF_TMP_A" "$SY_DIFF_TMP_B"' EXIT
  local ra=0 rb=0
  sy_kernel export md --id "$a" >"$tmpa" 2>/dev/null || ra=$?
  sy_kernel export md --id "$b" >"$tmpb" 2>/dev/null || rb=$?
  if [[ $ra -ne 0 || $rb -ne 0 ]]; then
    sy_die 1 "diff: 读取文档失败" "运行 'siyuan stat ${a_ref}' / 'siyuan stat ${b_ref}' 确认文档存在"
  fi

  local rc=0
  diff -u "$@" "$tmpa" "$tmpb" || rc=$?
  # 退出码透传: 0=相同 1=有差异 (同系统 diff); 其他视为错误
  if [[ $rc -eq 2 ]]; then
    sy_die 1 "diff: diff 执行失败" "检查传入的 diff 参数是否合法"
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# rename <doc> <新标题> — 重命名文档
#   1. document rename 改 IAL title (文档名)
#   2. 若有 H1 子块, block update 同步标题文本 (避免 title/H1 不一致)
#   注意: 绝不 block update 文档块本身 (会把整篇文档内容替换掉)
#   返回: 文档 id
# ---------------------------------------------------------------------------
cmd_rename() {
  local doc_ref="${1:-}" new_title="${2:-}"
  if [[ -z "$doc_ref" || -z "$new_title" ]]; then
    sy_die 2 "rename: 缺少文档或新标题" "用法: siyuan rename <doc-id|标题|/路径> <新标题>"
  fi
  local doc
  doc="$(sy_resolve_doc rename "$doc_ref")" || return $?
  sy_kernel_or_die rename document rename --id "$doc" --title "$new_title" >/dev/null

  # H1 子块同步 (第一个 h1; 无 H1 子块的文档跳过, 文档名即标题)
  local h1
  h1="$(sy_json rename sql "SELECT id FROM blocks WHERE root_id='$doc' AND type='h' AND subtype='h1' ORDER BY sort LIMIT 1" |
    "$SY_NODE" "$SY_LIB_DIR/fmt.js" ids)" || return $?
  h1="$(printf '%s\n' "$h1" | head -1)"
  if [[ -n "$h1" ]]; then
    sy_kernel_or_die rename block update --id "$h1" --data "# $new_title" >/dev/null
  fi
  echo "$doc"
}
