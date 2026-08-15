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
# 共享: 检测内核 HTTP API 是否可用 (写入兜底判定)
# ---------------------------------------------------------------------------
sy_http_up() { # stdout: 0=不可用 1=可用
  if curl -s -m 2 -o /dev/null -X POST "http://$SIYUAN_API_HOST:$SIYUAN_API_PORT/api/system/currentTime" \
    -H "Content-Type: application/json" -d '{}' 2>/dev/null; then
    echo 1
  else
    echo 0
  fi
}

# ---------------------------------------------------------------------------
# 共享: 创建文档 (createDocWithMd 三步语义: 建/移/删中间块, HTTP 不可用时回退 CLI)
#   sy_doc_create <ctx> <nbid> <title> <parent_id> <hpath> <md>
#   成功: stdout = 新文档 id
#   HTTP 路径: createDocWithMd 建在 hpath 下 → moveDocs 移到父文档 → 删中间块
#   CLI 路径:  document create --path <父文档内部目录> 直接建, 无中间块问题
# ---------------------------------------------------------------------------
sy_doc_create() {
  local ctx="$1" nbid="$2" title="$3" parent_id="$4" hpath="$5" md="$6"

  if [[ "$(sy_http_up)" == "1" ]]; then
    # --- HTTP 三步语义 (createDocWithMd + moveDocs + 删中间块) ---
    local doc_path
    if [[ -n "$parent_id" ]]; then
      local parent_hpath
      parent_hpath="$(sy_json "$ctx" sql "SELECT hpath FROM blocks WHERE id='$parent_id'" |
        "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field hpath)" || return $?
      if [[ -z "$parent_hpath" ]]; then
        sy_die 1 "$ctx: 找不到父文档 '$parent_id'" "用 'siyuan which $parent_id' 确认父文档存在"
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
      sy_die 1 "$ctx: 创建文档失败" "确认内核 HTTP API 在运行 (6806 端口)"
    fi

    # 2. 若指定 parent-id, 用 moveDocs 移到正确父块下 (避免重复中间块)
    if [[ -n "$parent_id" ]]; then
      local parent_dir new_from_path to_path
      parent_dir="$(sy_parent_dir "$ctx" "$parent_id")"
      new_from_path="$(sy_doc_path "$ctx" "$new_id")"
      to_path="${parent_dir}.sy"
      sy_http_api "/api/filetree/moveDocs" \
        "{\"fromPaths\":[\"$new_from_path\"],\"toNotebook\":\"$nbid\",\"toPath\":\"$to_path\"}" >/dev/null 2>&1
      # 删掉 createDocWithMd 产生的空中间块
      local t mid_block_id
      t="${new_from_path%/*}"
      mid_block_id="${t##*/}"
      mid_block_id="${mid_block_id%.sy}"
      if [[ -n "$mid_block_id" && "$mid_block_id" != "$parent_id" ]]; then
        sy_http_api "/api/filetree/removeDocByID" "{\"id\":\"$mid_block_id\"}" >/dev/null 2>&1
      fi
    fi
    echo "$new_id"
    return 0
  fi

  # --- CLI 回退 (App 未运行时) ---
  local cli_path="/"
  if [[ -n "$parent_id" ]]; then
    local pp
    pp="$(sy_json "$ctx" sql "SELECT path FROM blocks WHERE id='$parent_id'" |
      "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field path)" || return $?
    if [[ -z "$pp" ]]; then
      sy_die 1 "$ctx: 找不到父文档 '$parent_id'" "用 'siyuan which $parent_id' 确认父文档存在"
    fi
    cli_path="${pp%.sy}/"
  elif [[ -n "$hpath" ]]; then
    # hpath 需能定位到已存在文档 (取其内部目录); 定位不到时报错而非静默建到根
    local esc="${hpath//\'/\'\'}"
    local pp
    pp="$(sy_json "$ctx" sql "SELECT path FROM blocks WHERE hpath='$esc' AND type='d'" |
      "$SY_NODE" "$SY_LIB_DIR/fmt.js" first-field path)" || return $?
    if [[ -z "$pp" ]]; then
      sy_die 1 "$ctx: --path '$hpath' 无法定位到已存在文档" "改用 --parent <父文档id>, 或先创建中间文档"
    fi
    cli_path="${pp%.sy}/"
  fi
  local cargs=(document create --notebook "$nbid" --title "$title")
  [[ "$cli_path" != "/" ]] && cargs+=(--path "$cli_path")
  [[ -n "$md" ]] && cargs+=(--markdown "$md")
  local out rc=0
  out="$(sy_kernel "${cargs[@]}" 2>/dev/null)" || rc=$?
  if [[ $rc -eq 124 ]]; then
    sy_die 124 "$ctx: 内核 ${SIYUAN_TIMEOUT} 秒无响应" "重试, 或调大 SIYUAN_TIMEOUT 环境变量"
  elif [[ $rc -ne 0 ]]; then
    sy_die 1 "$ctx: 创建文档失败 (内核返回 $rc)" "运行 'siyuan raw document create --help' 查看参数"
  fi
  echo "$out"
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
    -h | --help)
      sy_usage write
      return 0
      ;;
    *) sy_die 2 "write: 未知参数 '$1'" "用法: siyuan write --notebook <nb> --title <t> [--parent-id <pid> | --path <hpath>] [--file <md>|stdin]" ;;
    esac
  done
  if [[ -z "$nb" || -z "$title" ]]; then
    sy_die 2 "write: 缺少 --notebook 或 --title" "用法: siyuan write --notebook <nb> --title <t> [--parent-id <pid> | --path <hpath>] [--file <md>|stdin]"
  fi
  local nbid
  nbid="$(sy_resolve_notebook write "$nb")" || return $?

  local md=""
  if [[ -n "$file" ]]; then
    md="$(cat "$file")"
  elif [[ ! -t 0 ]]; then
    md="$(cat)"
  fi

  sy_doc_create write "$nbid" "$title" "$parent_id" "$hpath" "$md" || return $?
}

# ---------------------------------------------------------------------------
# append <doc-id> [--data <md> | --file <f> | stdin]
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
    -h | --help)
      sy_usage append
      return 0
      ;;
    *) sy_die 2 "append: 未知参数 '$1'" "用法: siyuan append <doc-id> [--data <md> | --file <f> | stdin]" ;;
    esac
  done
  [[ -n "$id" ]] || sy_die 2 "append: 缺少文档 id" "用法: siyuan append <doc-id> [--data <md> | --file <f> | stdin]"
  if [[ -z "$data" && -n "$file" ]]; then data="$(cat "$file")"; fi
  if [[ -z "$data" && ! -t 0 ]]; then data="$(cat)"; fi
  [[ -n "$data" ]] || sy_die 2 "append: 没有提供内容" "用 --data <md> / --file <f> / 管道 stdin 传入内容"
  sy_kernel_or_die append block append --parent "$id" --data "$data"
}

# ---------------------------------------------------------------------------
# update-block <block-id> [--data <md> | --file <f>]
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
    -h | --help)
      sy_usage update-block
      return 0
      ;;
    *) sy_die 2 "update-block: 未知参数 '$1'" "用法: siyuan update-block <block-id> [--data <md> | --file <f>]" ;;
    esac
  done
  [[ -n "$id" ]] || sy_die 2 "update-block: 缺少块 id" "用法: siyuan update-block <block-id> [--data <md> | --file <f>]"
  if [[ -z "$data" && -n "$file" ]]; then data="$(cat "$file")"; fi
  if [[ -z "$data" && ! -t 0 ]]; then data="$(cat)"; fi
  sy_kernel_or_die update-block block update --id "$id" --data "$data"
  echo "ok"
}

# ---------------------------------------------------------------------------
# delete-block <block-id>
# ---------------------------------------------------------------------------
cmd_delete_block() {
  local id="${1:-}"
  [[ -n "$id" ]] || sy_die 2 "delete-block: 缺少块 id" "用法: siyuan delete-block <block-id>"
  sy_kernel_or_die delete-block block delete --id "$id"
  echo "ok"
}

# ---------------------------------------------------------------------------
# insert-block [--previous <bid> | --parent <doc-id>] [--data <md> | --file <f> | stdin]
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
    -h | --help)
      sy_usage insert-block
      return 0
      ;;
    *) sy_die 2 "insert-block: 未知参数 '$1'" "用法: siyuan insert-block --previous <bid> | --parent <doc-id> [--data <md>|--file <f>|stdin]" ;;
    esac
  done
  if [[ -z "$prev" && -z "$parent" ]]; then
    sy_die 2 "insert-block: 缺少 --previous 或 --parent" "用法: siyuan insert-block --previous <bid> | --parent <doc-id> [--data <md>|--file <f>|stdin]"
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
  sy_kernel_or_die insert-block "${iargs[@]}"
  echo "ok"
}

# ---------------------------------------------------------------------------
# 共享: 替换整篇文档内容 (删旧子块 + 追加新内容, 标题块保留)
#   sy_replace_doc <ctx> <doc-id> <data>
# ---------------------------------------------------------------------------
sy_replace_doc() {
  local ctx="$1" id="$2" data="$3"
  # 1. 删除文档下所有内容块 (root_id 查全部子块, 跳过文档块本身 type=d)
  local child_ids
  child_ids="$(sy_json "$ctx" sql "SELECT id FROM blocks WHERE root_id='$id' AND type != 'd'" |
    "$SY_NODE" "$SY_LIB_DIR/fmt.js" ids | tr '\n' ' ')" || return $?
  local cid
  for cid in $child_ids; do
    sy_kernel block delete --id "$cid" >/dev/null 2>&1 || true
  done
  # 2. 追加新内容
  sy_kernel_or_die "$ctx" block append --parent "$id" --data "$data"
}

# ---------------------------------------------------------------------------
# replace-doc <doc-id> [--data <md> | --file <f> | stdin]
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
    -h | --help)
      sy_usage replace-doc
      return 0
      ;;
    *) sy_die 2 "replace-doc: 未知参数 '$1'" "用法: siyuan replace-doc <doc-id> [--data <md> | --file <f> | stdin]" ;;
    esac
  done
  [[ -n "$id" ]] || sy_die 2 "replace-doc: 缺少文档 id" "用法: siyuan replace-doc <doc-id> [--data <md> | --file <f> | stdin]"
  if [[ -z "$data" && -n "$file" ]]; then data="$(cat "$file")"; fi
  if [[ -z "$data" && ! -t 0 ]]; then data="$(cat)"; fi
  [[ -n "$data" ]] || sy_die 2 "replace-doc: 没有提供内容" "用 --data <md> / --file <f> / 管道 stdin 传入内容"
  sy_replace_doc replace-doc "$id" "$data" || return $?
  echo "ok"
}

# ---------------------------------------------------------------------------
# move <doc-id> --parent-id <pid> — 移动文档 (同/跨笔记本均走 HTTP moveDocs)
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
    -h | --help)
      sy_usage move
      return 0
      ;;
    *) sy_die 2 "move: 未知参数 '$1'" "用法: siyuan move <doc-id> --parent-id <parent-doc-id>" ;;
    esac
  done
  if [[ -z "$id" || -z "$parent_id" ]]; then
    sy_die 2 "move: 缺少文档 id 或 --parent-id" "用法: siyuan move <doc-id> --parent-id <parent-doc-id>"
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
  echo "ok"
}

# ---------------------------------------------------------------------------
# 共享: 删除文档 (CLI 优先, 失败兜底 HTTP removeDocByID)
#   sy_doc_delete <ctx> <doc-id>
# ---------------------------------------------------------------------------
sy_doc_delete() {
  local ctx="$1" id="$2"
  local rc=0
  sy_kernel document remove --id "$id" >/dev/null 2>&1 || rc=$?
  if [[ $rc -ne 0 ]]; then
    sy_http_api "/api/filetree/removeDocByID" "{\"id\":\"$id\"}" >/dev/null 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
# remove <doc-id> — 删除文档 (CLI 失败时兜底 HTTP removeDocByID)
# ---------------------------------------------------------------------------
cmd_remove() {
  local id="${1:-}"
  [[ -n "$id" ]] || sy_die 2 "remove: 缺少文档 id" "用法: siyuan remove <doc-id>"
  sy_doc_delete remove "$id"
  echo "$id"
}
