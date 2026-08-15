#!/usr/bin/env bash
# siyuan 写入/编辑命令组: write / append / insert-block / update-block / delete-block /
#                         replace-doc / move / remove
# 从旧单文件封装移植, 行为保持一致, 错误处理统一走框架

# 调用思源 HTTP API (内核 serve 运行时可用; 写入走 CLI 失败时的兜底/路径类操作)
#   sy_http_api <endpoint> <json-body> — stdout: 原始 JSON 响应
sy_http_api() {
  local endpoint="$1" body="$2"
  curl -s -m 10 -X POST "http://$SIYUAN_API_HOST:$SIYUAN_API_PORT$endpoint" \
    -H "Content-Type: application/json" -d "$body" 2>/dev/null
}

# http_api 但把 data 字段提取出来
sy_http_api_data() {
  local endpoint="$1" body="$2"
  sy_http_api "$endpoint" "$body" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" http-data
}

# 取文档 internal path (含 .sy)
sy_doc_path() { # <ctx> <doc-id>
  sy_json "$1" sql "SELECT path FROM blocks WHERE id='$2'" |
    "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field path || return $?
}

# 取父文档的 internal path (作为目录, 不含 .sy)
sy_parent_dir() { # <ctx> <parent-doc-id>
  local p
  p="$(sy_doc_path "$1" "$2")"
  echo "${p%.sy}"
}

# ---------------------------------------------------------------------------
# write — 创建文档. 用法:
#   siyuan write --notebook <nb> --title <t> [--parent-id <pid> | --path <hpath>] [--file <md>]
#   echo 'md...' | siyuan write --notebook <nb> --title <t> --parent-id <pid>
#   返回: 新文档 id
# ---------------------------------------------------------------------------
cmd_write() {
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
    --parent-id)
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
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage write
      return 0
      ;;
    *) sy_die 2 "write: 未知参数 '$1'" "用法: siyuan write --notebook <nb> --title <t> [--parent-id <pid> | --path <hpath>] [--file <md>|stdin] [--json|--markdown]" ;;
    esac
  done
  if [[ -z "$nb" || -z "$title" ]]; then
    sy_die 2 "write: 缺少 --notebook 或 --title" "用法: siyuan write --notebook <nb> --title <t> [--parent-id <pid> | --path <hpath>] [--file <md>|stdin] [--json|--markdown]"
  fi
  local nbid
  nbid="$(sy_resolve_notebook write "$nb")" || return $?

  local md=""
  if [[ -n "$file" ]]; then
    md="$(cat "$file")"
  elif [[ ! -t 0 ]]; then
    md="$(cat)"
  fi

  # createDocWithMd 的 path 参数 (完整文档路径 = 父hpath + 文档名)
  local doc_path
  if [[ -n "$parent_id" ]]; then
    local parent_hpath
    parent_hpath="$(sy_json write sql "SELECT hpath FROM blocks WHERE id='$parent_id'" |
      "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field hpath)" || return $?
    if [[ -z "$parent_hpath" ]]; then
      sy_die 1 "write: 找不到父文档 '$parent_id'" "用 'siyuan which $parent_id' 确认父文档存在"
    fi
    doc_path="${parent_hpath}/${title}"
  elif [[ -n "$hpath" ]]; then
    doc_path="${hpath}/${title}"
  else
    doc_path="/${title}"
  fi

  # 1. createDocWithMd 创建 (可能产生重复中间块, 后面清理)
  local new_id
  new_id="$(printf '%s' "$md" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" http-create "$SIYUAN_API_HOST" "$SIYUAN_API_PORT" "$nbid" "$doc_path")"
  if [[ -z "$new_id" ]]; then
    sy_die 1 "write: 创建文档失败" "确认内核 HTTP API 在运行 (6806 端口), 或用 'siyuan raw document create' 走 CLI"
  fi

  # 2. 若指定 parent-id, 用 moveDocs 移到正确父块下 (避免重复中间块)
  if [[ -n "$parent_id" ]]; then
    local parent_dir new_from_path to_path
    parent_dir="$(sy_parent_dir write "$parent_id")"
    new_from_path="$(sy_doc_path write "$new_id")"
    to_path="${parent_dir}.sy"
    sy_http_api "/api/filetree/moveDocs" \
      "{\"fromPaths\":[\"$new_from_path\"],\"toNotebook\":\"$nbid\",\"toPath\":\"$to_path\"}" >/dev/null 2>&1
    # 删掉 createDocWithMd 产生的空中间块
    local mid_block_id
    # 中间块 = new_from_path 的倒数第二段 (id 形式)
    local t="${new_from_path%/*}"
    local mid_block_id="${t##*/}"
    mid_block_id="${mid_block_id%.sy}"
    if [[ -n "$mid_block_id" && "$mid_block_id" != "$parent_id" ]]; then
      sy_http_api "/api/filetree/removeDocByID" "{\"id\":\"$mid_block_id\"}" >/dev/null 2>&1
    fi
  fi

  case "$SY_MODE" in
  json)
    printf '%s' "$new_id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" json-ok-doc "$new_id" "$title" 写入
    ;;
  markdown)
    # 确认块: 文档 id + 标题 + 链接 (可直接粘贴进思源/重定向到 .md)
    printf '%s' "$new_id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ok-doc "$new_id" "$title" 写入
    ;;
  *)
    echo "$new_id"
    ;;
  esac
}

# ---------------------------------------------------------------------------
# append <doc-id> [--data <md> | --file <f> | stdin] [--json|--markdown]
# ---------------------------------------------------------------------------
cmd_append() {
  local id="${1:-}"
  shift
  local data="" file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --data | -d)
      data="${2:?}"
      shift 2
      ;;
    --file | -f)
      file="${2:?}"
      shift 2
      ;;
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage append
      return 0
      ;;
    *) sy_die 2 "append: 未知参数 '$1'" "用法: siyuan append <doc-id> [--data <md> | --file <f> | stdin] [--json|--markdown]" ;;
    esac
  done
  [[ -n "$id" ]] || sy_die 2 "append: 缺少文档 id" "用法: siyuan append <doc-id> [--data <md> | --file <f> | stdin] [--json|--markdown]"
  if [[ -z "$data" && -n "$file" ]]; then data="$(cat "$file")"; fi
  if [[ -z "$data" && ! -t 0 ]]; then data="$(cat)"; fi
  [[ -n "$data" ]] || sy_die 2 "append: 没有提供内容" "用 --data <md> / --file <f> / 管道 stdin 传入内容"
  if [[ "$SY_MODE" == "text" ]]; then
    sy_kernel_or_die append block append --parent "$id" --data "$data"
  else
    # --json/--markdown: 抑制内核原始输出, 出确认块/稳定字段
    sy_kernel_capture append block append --parent "$id" --data "$data" >/dev/null || return $?
    local title
    title="$(sy_doc_title append "$id")" || return $?
    case "$SY_MODE" in
    json)
      printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" json-ok-doc "$id" "$title" 追加
      ;;
    markdown)
      printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ok-doc "$id" "$title" 追加
      ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# update-block <block-id> [--data <md> | --file <f>] [--json|--markdown]
# ---------------------------------------------------------------------------
cmd_update_block() {
  local id="${1:-}"
  shift
  local data="" file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --data | -d)
      data="${2:?}"
      shift 2
      ;;
    --file | -f)
      file="${2:?}"
      shift 2
      ;;
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage update-block
      return 0
      ;;
    *) sy_die 2 "update-block: 未知参数 '$1'" "用法: siyuan update-block <block-id> [--data <md> | --file <f>] [--json|--markdown]" ;;
    esac
  done
  [[ -n "$id" ]] || sy_die 2 "update-block: 缺少块 id" "用法: siyuan update-block <block-id> [--data <md> | --file <f>] [--json|--markdown]"
  if [[ -z "$data" && -n "$file" ]]; then data="$(cat "$file")"; fi
  if [[ -z "$data" && ! -t 0 ]]; then data="$(cat)"; fi
  if [[ "$SY_MODE" == "text" ]]; then
    sy_kernel_or_die update-block block update --id "$id" --data "$data"
    echo "ok"
  else
    sy_kernel_capture update-block block update --id "$id" --data "$data" >/dev/null || return $?
    case "$SY_MODE" in
    json)
      printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" json-ok-block "$id" 更新
      ;;
    markdown)
      printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ok-block "$id" 更新
      ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# delete-block <block-id> [--json|--markdown]
# ---------------------------------------------------------------------------
cmd_delete_block() {
  local id="${1:-}"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage delete-block
      return 0
      ;;
    *) sy_die 2 "delete-block: 未知参数 '$1'" "用法: siyuan delete-block <block-id> [--json|--markdown]" ;;
    esac
  done
  [[ -n "$id" ]] || sy_die 2 "delete-block: 缺少块 id" "用法: siyuan delete-block <block-id> [--json|--markdown]"
  if [[ "$SY_MODE" == "text" ]]; then
    sy_kernel_or_die delete-block block delete --id "$id"
    echo "ok"
  else
    sy_kernel_capture delete-block block delete --id "$id" >/dev/null || return $?
    case "$SY_MODE" in
    json)
      printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" json-ok-block "$id" 删除
      ;;
    markdown)
      printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ok-block "$id" 删除
      ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# insert-block [--previous <bid> | --parent <doc-id>] [--data <md> | --file <f> | stdin] [--json|--markdown]
#   块插入要求 parent 必填, --previous 只是兄弟锚点 (传 --previous 时自动查 parent)
# ---------------------------------------------------------------------------
cmd_insert_block() {
  local prev="" parent="" data="" file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --previous)
      prev="${2:?}"
      shift 2
      ;;
    --parent | -p)
      parent="${2:?}"
      shift 2
      ;;
    --data | -d)
      data="${2:?}"
      shift 2
      ;;
    --file | -f)
      file="${2:?}"
      shift 2
      ;;
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage insert-block
      return 0
      ;;
    *) sy_die 2 "insert-block: 未知参数 '$1'" "用法: siyuan insert-block --previous <bid> | --parent <doc-id> [--data <md>|--file <f>|stdin] [--json|--markdown]" ;;
    esac
  done
  if [[ -z "$prev" && -z "$parent" ]]; then
    sy_die 2 "insert-block: 缺少 --previous 或 --parent" "用法: siyuan insert-block --previous <bid> | --parent <doc-id> [--data <md>|--file <f>|stdin] [--json|--markdown]"
  fi
  if [[ -z "$data" && -n "$file" ]]; then data="$(cat "$file")"; fi
  if [[ -z "$data" && ! -t 0 ]]; then data="$(cat)"; fi
  [[ -n "$data" ]] || sy_die 2 "insert-block: 没有提供内容" "用 --data <md> / --file <f> / 管道 stdin 传入内容"
  if [[ -n "$prev" && -z "$parent" ]]; then
    parent="$(sy_json insert-block sql "SELECT parent_id FROM blocks WHERE id='$prev'" |
      "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field parent_id)" || return $?
    if [[ -z "$parent" ]]; then
      sy_die 1 "insert-block: 无法解析 previous 块的 parent" "显式传 --parent <doc-id>"
    fi
  fi
  local iargs=(block insert --parent "$parent" --data "$data")
  [[ -n "$prev" ]] && iargs+=(--previous "$prev")
  if [[ "$SY_MODE" == "text" ]]; then
    sy_kernel_or_die insert-block "${iargs[@]}"
    echo "ok"
  else
    sy_kernel_capture insert-block "${iargs[@]}" >/dev/null || return $?
    case "$SY_MODE" in
    json)
      printf '%s' "$parent" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" json-ok-block "$parent" 插入
      ;;
    markdown)
      printf '%s' "$parent" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ok-block "$parent" 插入
      ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# replace-doc <doc-id> [--data <md> | --file <f> | stdin] [--json|--markdown]
#   ⚠ 先删文档下所有子块, 再写入新 markdown (标题块保留)
# ---------------------------------------------------------------------------
cmd_replace_doc() {
  local id="${1:-}"
  shift
  local data="" file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --data | -d)
      data="${2:?}"
      shift 2
      ;;
    --file | -f)
      file="${2:?}"
      shift 2
      ;;
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage replace-doc
      return 0
      ;;
    *) sy_die 2 "replace-doc: 未知参数 '$1'" "用法: siyuan replace-doc <doc-id> [--data <md> | --file <f> | stdin] [--json|--markdown]" ;;
    esac
  done
  [[ -n "$id" ]] || sy_die 2 "replace-doc: 缺少文档 id" "用法: siyuan replace-doc <doc-id> [--data <md> | --file <f> | stdin] [--json|--markdown]"
  if [[ -z "$data" && -n "$file" ]]; then data="$(cat "$file")"; fi
  if [[ -z "$data" && ! -t 0 ]]; then data="$(cat)"; fi
  [[ -n "$data" ]] || sy_die 2 "replace-doc: 没有提供内容" "用 --data <md> / --file <f> / 管道 stdin 传入内容"
  # 1. 删除文档下所有内容块 (root_id 查全部子块, 跳过文档块本身 type=d)
  local child_ids
  child_ids="$(sy_json replace-doc sql "SELECT id FROM blocks WHERE root_id='$id' AND type != 'd'" |
    "$SY_NODE" "$SY_LIB_DIR/fmt.js" ids | tr '\n' ' ')" || return $?
  local cid
  for cid in $child_ids; do
    sy_kernel block delete --id "$cid" >/dev/null 2>&1 || true
  done
  # 2. 追加新内容
  if [[ "$SY_MODE" == "text" ]]; then
    sy_kernel_or_die replace-doc block append --parent "$id" --data "$data"
    echo "ok"
  else
    sy_kernel_capture replace-doc block append --parent "$id" --data "$data" >/dev/null || return $?
    local title
    title="$(sy_doc_title replace-doc "$id")" || return $?
    case "$SY_MODE" in
    json)
      printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" json-ok-doc "$id" "$title" 替换
      ;;
    markdown)
      printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ok-doc "$id" "$title" 替换
      ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# move <doc-id> --parent-id <pid> [--json|--markdown] — 移动文档 (同/跨笔记本均走 HTTP moveDocs)
# ---------------------------------------------------------------------------
cmd_move() {
  local id="${1:-}"
  shift
  local parent_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --parent-id | -p)
      parent_id="${2:?}"
      shift 2
      ;;
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage move
      return 0
      ;;
    *) sy_die 2 "move: 未知参数 '$1'" "用法: siyuan move <doc-id> --parent-id <parent-doc-id> [--json|--markdown]" ;;
    esac
  done
  if [[ -z "$id" || -z "$parent_id" ]]; then
    sy_die 2 "move: 缺少文档 id 或 --parent-id" "用法: siyuan move <doc-id> --parent-id <parent-doc-id> [--json|--markdown]"
  fi
  # 标题在移动前解析 (moveDocs 后 hpath 索引可能短暂滞后)
  local title=""
  if [[ "$SY_MODE" != "text" ]]; then
    title="$(sy_doc_title move "$id")" || return $?
  fi
  local from_path to_path nbid
  from_path="$(sy_doc_path move "$id")"
  to_path="$(sy_doc_path move "$parent_id")"
  nbid="$(sy_json move sql "SELECT box FROM blocks WHERE id='$id'" |
    "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field box)" || return $?
  if [[ -z "$from_path" || -z "$to_path" || -z "$nbid" ]]; then
    sy_die 1 "move: 无法解析文档路径" "用 'siyuan which $id' / 'siyuan which $parent_id' 确认文档存在"
  fi
  local rc=0
  sy_http_api "/api/filetree/moveDocs" \
    "{\"fromPaths\":[\"$from_path\"],\"toNotebook\":\"$nbid\",\"toPath\":\"$to_path\"}" >/dev/null || rc=$?
  if [[ $rc -ne 0 ]]; then
    sy_die 1 "move: 移动失败" "确认内核 HTTP API 在运行 (6806 端口)"
  fi
  case "$SY_MODE" in
  json)
    printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" json-ok-doc "$id" "$title" 移动
    ;;
  markdown)
    printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ok-doc "$id" "$title" 移动
    ;;
  *)
    echo "ok"
    ;;
  esac
}

# ---------------------------------------------------------------------------
# remove <doc-id> [--json|--markdown] — 删除文档 (CLI 失败时兜底 HTTP removeDocByID)
# ---------------------------------------------------------------------------
cmd_remove() {
  local id="${1:-}"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json | --markdown)
      sy_mode_arg "$1"
      shift
      ;;
    -h | --help)
      sy_usage remove
      return 0
      ;;
    *) sy_die 2 "remove: 未知参数 '$1'" "用法: siyuan remove <doc-id> [--json|--markdown]" ;;
    esac
  done
  [[ -n "$id" ]] || sy_die 2 "remove: 缺少文档 id" "用法: siyuan remove <doc-id> [--json|--markdown]"
  # 标题在删除前解析 (删除后查不到)
  local title=""
  if [[ "$SY_MODE" != "text" ]]; then
    title="$(sy_doc_title remove "$id")" || return $?
  fi
  local rc=0
  if [[ "$SY_MODE" == "text" ]]; then
    sy_kernel document remove --id "$id" 2>/dev/null || rc=$?
  else
    # --json/--markdown: 抑制内核原始输出 (stdout 只含模式输出)
    sy_kernel document remove --id "$id" >/dev/null 2>&1 || rc=$?
  fi
  if [[ $rc -ne 0 ]]; then
    sy_http_api "/api/filetree/removeDocByID" "{\"id\":\"$id\"}" >/dev/null 2>&1 || true
  fi
  case "$SY_MODE" in
  json)
    printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" json-ok-remove "$id" "$title"
    ;;
  markdown)
    printf '%s' "$id" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" md-ok-remove "$id" "$title"
    ;;
  *)
    : # 文本模式维持原行为 (无输出)
    ;;
  esac
}
