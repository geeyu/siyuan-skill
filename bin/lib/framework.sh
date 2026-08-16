#!/usr/bin/env bash
# siyuan 框架层: 环境配置 / 命令注册表 / 内核调用 (超时) / 统一错误与输出
#
# 设计契约 (所有命令遵守):
#   退出码: 0=成功, 1=业务/运行时错误, 2=用法错误, 3=配置错误, 124=超时
#   错误:   写 stderr, 格式 "siyuan <命令>: <原因>", 可操作 (带建议)
#   输出:   默认人类可读文本 (行式, 可被其他命令消费); --json 输出稳定字段;
#           --markdown 输出 markdown (表格/列表/确认块, stdout 只含 markdown 可重定向)
#   模式:   --json 与 --markdown 互斥 (同时给报用法错误); 由 sy_mode_arg 统一解析
#   环境:   SIYUAN_KERNEL / SIYUAN_WORKSPACE / SIYUAN_FORMAT / SIYUAN_TIMEOUT /
#           SIYUAN_DEFAULT_NOTEBOOK / SIYUAN_API_HOST / SIYUAN_API_PORT

# ---------------------------------------------------------------------------
# 配置 (可被环境变量覆盖)
# ---------------------------------------------------------------------------
SIYUAN_KERNEL="${SIYUAN_KERNEL:-/Applications/SiYuan.app/Contents/Resources/kernel/SiYuan-Kernel}"
SIYUAN_WORKSPACE="${SIYUAN_WORKSPACE:-/Users/geeyu/space/siyuan}"
SIYUAN_FORMAT="${SIYUAN_FORMAT:-text}"                 # text | json (json = 默认 --json)
SIYUAN_TIMEOUT="${SIYUAN_TIMEOUT:-60}"                 # 内核调用超时(秒), 0=不超时
SIYUAN_DEFAULT_NOTEBOOK="${SIYUAN_DEFAULT_NOTEBOOK:-}" # 设置后 `ls` 默认列该笔记本
SIYUAN_API_HOST="${SIYUAN_API_HOST:-127.0.0.1}"
SIYUAN_API_PORT="${SIYUAN_API_PORT:-6806}"

# 当前命令名 (错误信息前缀, 由分发器设置)
SY_CMD_NAME="siyuan"

# lib 目录 (fmt.js 等助手所在)
SY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# node 定位 (PATH → fnm → brew, 与 wf CLI 同策略; 本机 PATH 常无 node)
SY_NODE="$(command -v node 2>/dev/null || true)"
if [[ -z "$SY_NODE" ]]; then
  for d in "$HOME"/.local/share/fnm/node-versions/*/installation/bin/node "$HOME"/.fnm/node-versions/*/installation/bin/node /opt/homebrew/bin/node; do
    if [[ -x "$d" ]]; then
      SY_NODE="$d"
      break
    fi
  done
fi
if [[ -z "$SY_NODE" ]]; then
  echo "siyuan: 找不到 node 运行时 (fmt.js 依赖)" >&2
  echo "  建议: 安装 node (brew install node), 或把 node 加入 PATH" >&2
  exit 3
fi

# --json 默认值 (SIYUAN_FORMAT=json 时全局默认开启; 被各命令模块读取)
# shellcheck disable=SC2034 # 跨文件使用 (cmd-query.sh / cmd-misc.sh)
SY_JSON_DEFAULT=0
# shellcheck disable=SC2034
[[ "$SIYUAN_FORMAT" == "json" ]] && SY_JSON_DEFAULT=1

# 输出模式 (框架统一路由): text | json | markdown
#   sy_dispatch 每次调用前按 SIYUAN_FORMAT 初始化; 命令参数循环用 sy_mode_arg 消费标志
# shellcheck disable=SC2034 # 跨文件使用 (cmd-query.sh / cmd-misc.sh / cmd-write.sh / cmd-av.sh)
SY_MODE=text

# ---------------------------------------------------------------------------
# 命令注册表 (bash 3.2 无关联数组, 用并行数组)
# ---------------------------------------------------------------------------
SY_CMD_NAMES=()
SY_CMD_HANDLERS=()

# sy_register <命令名> <处理函数> [别名...]
sy_register() {
  local name="$1" handler="$2"
  shift 2
  SY_CMD_NAMES+=("$name")
  SY_CMD_HANDLERS+=("$handler")
  local a
  for a in "$@"; do
    SY_CMD_NAMES+=("$a")
    SY_CMD_HANDLERS+=("$handler")
  done
}

# sy_dispatch <命令名> <args...> — 查注册表分发 (含别名), 返回处理函数退出码
sy_dispatch() {
  local cmd="$1"
  shift
  # 输出模式初始化 (每次调用重置; SIYUAN_FORMAT=json 时默认 json)
  SY_MODE=text
  [[ "$SIYUAN_FORMAT" == "json" ]] && SY_MODE=json
  local i
  for i in "${!SY_CMD_NAMES[@]}"; do
    if [[ "${SY_CMD_NAMES[$i]}" == "$cmd" ]]; then
      "${SY_CMD_HANDLERS[$i]}" "$@"
      return $?
    fi
  done
  return 255
}

# ---------------------------------------------------------------------------
# 统一错误: 命令名 / 原因 / 建议, 写 stderr
# ---------------------------------------------------------------------------
sy_die() { # sy_die <退出码> <原因> [建议]
  local code="$1" msg="$2" sug="${3:-}"
  echo "siyuan $SY_CMD_NAME: $msg" >&2
  [[ -n "$sug" ]] && echo "  建议: $sug" >&2
  exit "$code"
}

# ---------------------------------------------------------------------------
# 输出模式标志 (框架统一路由; 各命令参数循环调用, 消费 --json / --markdown)
#   sy_mode_arg <arg>: 命中模式标志返回 0 (设置 SY_MODE); 其他参数返回 255
#   互斥: --json 与 --markdown 同时出现 → 用法错误 (退出 2)
# ---------------------------------------------------------------------------
sy_mode_arg() {
  case "$1" in
  --json)
    if [[ "$SY_MODE" == "markdown" ]]; then
      sy_die 2 "$SY_CMD_NAME: --json 与 --markdown 不能同时使用" "输出模式三选一: 默认文本 / --json / --markdown"
    fi
    SY_MODE=json
    return 0
    ;;
  --markdown)
    if [[ "$SY_MODE" == "json" ]]; then
      sy_die 2 "$SY_CMD_NAME: --json 与 --markdown 不能同时使用" "输出模式三选一: 默认文本 / --json / --markdown"
    fi
    SY_MODE=markdown
    return 0
    ;;
  esac
  return 255
}

# ---------------------------------------------------------------------------
# 内核调用 (统一 -w / 超时 / 输出捕获)
#   sy_kernel [-f] <args...>
#     -f      加 -f json (结构化输出)
#     成功: stdout = 内核 stdout; SY_KERNEL_RC=0
#     失败: SY_KERNEL_RC≠0, SY_KERNEL_ERR = 内核 stderr (统一回显)
# ---------------------------------------------------------------------------
sy_kernel() {
  local want_json=0
  if [[ "${1:-}" == "-f" ]]; then
    want_json=1
    shift
  fi
  local args=(-w "$SIYUAN_WORKSPACE")
  [[ $want_json -eq 1 ]] && args+=(-f json)
  args+=("$@")
  # 超时控制交给 node child_process (macOS 无 timeout 命令;
  # bash 3.2 在命令替换中多后台 job 时 wait 会卡死, 故不用 wait+sleep-kill 方案)
  # stdout 直通, 内核 stderr 直接穿透 (错误信息即时可见)
  "$SY_NODE" - "$SIYUAN_TIMEOUT" "$SIYUAN_KERNEL" "${args[@]}" <<'JS' || return $?
const { spawnSync } = require('child_process');
const fs = require('fs');
const timeout = parseFloat(process.argv[2]);
const kernel = process.argv[3];
const args = process.argv.slice(4);
const r = spawnSync(kernel, args, {
  timeout: timeout > 0 ? timeout * 1000 : undefined,
  maxBuffer: 1024 * 1024 * 64,
});
// 同步写 fd 1/2: 异步 write 在输出 >管道缓冲(约 64KB)时会因进程提前退出而截断
if (r.error) {
  if (r.error.code === 'ETIMEDOUT') {
    fs.writeSync(2, 'siyuan: kernel timed out after ' + timeout + ' seconds\n');
    process.exit(124);
  }
  fs.writeSync(2, 'siyuan: kernel spawn error: ' + r.error.message + '\n');
  process.exit(3);
}
if (r.stderr) fs.writeSync(2, r.stderr);
fs.writeSync(1, r.stdout || '');
if (r.signal) {
  fs.writeSync(2, 'siyuan: kernel timed out after ' + timeout + ' seconds\n');
  process.exit(124);
}
process.exit(r.status === null ? 1 : r.status);
JS
}

# 内核调用 + JSON 校验; 失败统一报错退出 (超时=124, 其余=1)
#   sy_json <上下文> <args...> — stdout: 内核 JSON
sy_json() {
  local ctx="$1"
  shift
  local out rc=0
  out="$(sy_kernel -f "$@")" || rc=$?
  if [[ $rc -eq 124 ]]; then
    sy_die 124 "$ctx: 内核 ${SIYUAN_TIMEOUT} 秒无响应" "重试, 或调大 SIYUAN_TIMEOUT 环境变量"
  elif [[ $rc -ne 0 ]]; then
    sy_die 1 "$ctx: 内核调用失败 (见上方内核错误)" "运行 'siyuan raw-help $ctx' 查看底层命令参数"
  fi
  if ! printf '%s' "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" check 2>/dev/null; then
    sy_die 1 "$ctx: 内核返回非 JSON 输出" "运行 'siyuan raw $ctx --help' 排查"
  fi
  echo "$out"
}

# 内核调用 + 非零即报错 (用于文本输出类; 不校验 JSON)
#   sy_kernel_or_die <上下文> <args...> — stdout: 内核输出
sy_kernel_or_die() {
  local ctx="$1"
  shift
  local rc=0
  sy_kernel "$@" || rc=$?
  if [[ $rc -eq 124 ]]; then
    sy_die 124 "$ctx: 内核 ${SIYUAN_TIMEOUT} 秒无响应" "重试, 或调大 SIYUAN_TIMEOUT 环境变量"
  elif [[ $rc -ne 0 ]]; then
    sy_die 1 "$ctx: 内核调用失败 (见上方内核错误)" "运行 'siyuan raw-help $ctx' 查看底层命令参数"
  fi
}

# 内核调用 + 非零即报错, stdout 捕获 (--json/--markdown 模式需要抑制内核原始输出时用)
#   sy_kernel_capture <上下文> <args...> — stdout: 内核输出 (已捕获); 失败统一 sy_die
sy_kernel_capture() {
  local ctx="$1"
  shift
  local out rc=0
  out="$(sy_kernel "$@")" || rc=$?
  if [[ $rc -eq 124 ]]; then
    sy_die 124 "$ctx: 内核 ${SIYUAN_TIMEOUT} 秒无响应" "重试, 或调大 SIYUAN_TIMEOUT 环境变量"
  elif [[ $rc -ne 0 ]]; then
    sy_die 1 "$ctx: 内核调用失败 (见上方内核错误)" "运行 'siyuan raw-help $ctx' 查看底层命令参数"
  fi
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# markdown 输出助手 (框架统一路由; 渲染逻辑在 fmt.js, 这里只准备数据)
# ---------------------------------------------------------------------------

# 笔记本 id→名称 映射行 (md 渲染用; 一次内核调用)
#   sy_nb_names <ctx> -> stdout: "id<TAB>name" 每行 (供 fmt.js NB_NAMES 环境变量)
sy_nb_names() {
  local ctx="$1"
  sy_json "$ctx" notebook list | "$SY_NODE" "$SY_LIB_DIR/fmt.js" tsv id name || return $?
}

# 单个笔记本 id → 名称 (查不到原样返回 id)
sy_nb_name() { # <ctx> <box-id>
  local ctx="$1" box="$2" out name
  out="$(sy_nb_names "$ctx")" || return $?
  name="$(printf '%s\n' "$out" | awk -F '\t' -v id="$box" '$1==id {print $2; exit}')"
  echo "${name:-$box}"
}

# doc id → 标题 (hpath 末段); 查不到输出空
sy_doc_title() { # <ctx> <doc-id>
  local ctx="$1" id="$2" meta hpath
  meta="$(sy_doc_meta "$ctx" "$id")" || return $?
  hpath="${meta%%$'\t'*}"
  [[ -n "$hpath" ]] && echo "${hpath##*/}"
}

# ---------------------------------------------------------------------------
# 输出助手
# ---------------------------------------------------------------------------

# stdin: JSON (对象或数组) -> stdout: TSV 行 (字段按给定顺序, 缺失/空值留空)
#   sy_tsv <字段...>
sy_tsv() {
  local fields=("$@")
  "$SY_NODE" "$SY_LIB_DIR/fmt.js" tsv "${fields[@]}"
}

# ---------------------------------------------------------------------------
# 业务解析助手
# ---------------------------------------------------------------------------

# 解析笔记本引用 (id 或名字) -> stdout: notebook id; 找不到输出空 (不报错)
#   注意: id 形态 (14位时间戳-字母数字) 不直接放行 — doc id 同形态, 必须查 notebook list 验证
sy_resolve_notebook_soft() { # <ctx> <id或名字>
  local ctx="$1" nb="$2"
  [[ -n "$nb" ]] || return 0
  local out id
  out="$(sy_json "$ctx" notebook list)" || return $?
  id="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" find-by-field id "$nb" id)"
  [[ -n "$id" ]] || id="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" find-by-field name "$nb" id)"
  [[ -n "$id" ]] && echo "$id"
  return 0
}

# 解析笔记本引用 (id 或名字) -> stdout: notebook id; 失败 sy_die
sy_resolve_notebook() { # <ctx> <id或名字>
  local ctx="$1" nb="$2"
  local id
  id="$(sy_resolve_notebook_soft "$ctx" "$nb")" || return $?
  if [[ -z "$id" ]]; then
    sy_die 1 "$ctx: 找不到笔记本 '$nb'" "运行 'siyuan ls' 查看可用笔记本 (支持传 id 或中文名)"
  fi
  echo "$id"
}

# 定位文档引用 (id / 标题 / 路径) -> stdout: JSON 数组 [{id,hPath,box}]
#   规则: id 精确查; 含 / 的引用先按 hpath 精确匹配, 无匹配则尝试
#         「笔记本名 + hPath」(如 /工作/调课, 或 find 输出直接复制的 工作/调课);
#         仍无匹配回退标题搜索 (document search, 精确同名优先, 再宽松匹配)
# 路径后缀匹配 (部分路径 /AI伴学 → hpath 后缀), LIKE 特殊字符转义
sy_locate_suffix() { # <ctx> <去前导/的路径段> [box 限定] -> stdout: JSON 数组 (可为空)
  local ctx="$1" seg="$2" box="${3:-}"
  local esc="${seg//\'/\'\'}"
  esc="${esc//%/\\%}"
  esc="${esc//_/\\_}"
  local sql="SELECT id, hpath, box FROM blocks WHERE hpath LIKE '%/$esc' AND type='d'"
  [[ -n "$box" ]] && sql+=" AND box='$box'"
  sy_json "$ctx" sql "$sql"
}

# 定位文档引用 (id / 标题 / 路径) -> stdout: JSON 数组 [{id,hPath,box}]
#   统一解析链 (多匹配一律交给上层列候选):
#     1. id 精确
#     2. 完整路径 / 笔记本名+路径 (带不带前导 / 均可)
#     3. hpath 精确 (无笔记本名)
#     4. 路径后缀匹配 (部分路径, 如 /AI伴学)
#     5. 标题搜索 (精确同名优先; 无 / 引用先标题, 空则补后缀匹配目录名)
# 文档引用统一解析链 (多匹配一律交给上层列候选):
#   / 开头 (路径语义):
#     a. 完整路径精确: hpath 整段 (含笔记本名时先试, 命中即用)
#     b. 「笔记本名 + 剩余路径」精确 (find/ls 输出格式)
#     c. 路径后缀匹配 (部分路径, 如 /AI伴学)
#     d. 标题搜索回退
#   无 / 开头:
#     e. 含 / 时按 b/c 处理 (工作/调课)
#     f. 标题搜索 (精确同名优先)
#     g. 标题空则后缀匹配 (目录名场景, 如 cat AI伴学)
sy_locate_docs() { # <ctx> <引用>
  local ctx="$1" ref="$2"
  local out names
  names="$(sy_nb_names "$ctx")" || return $?
  if [[ "$ref" =~ ^[0-9]{14}-[a-z0-9]{6,8}$ ]]; then
    out="$(sy_json "$ctx" sql "SELECT id, hpath, box FROM blocks WHERE id='$ref' AND type='d'")" || return $?
    echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" docs-sql
    return 0
  fi
  local work="${ref#/}"
  local esc="${work//\'/\'\'}"
  if [[ "$ref" == /* ]]; then
    # a. hpath 整段精确
    out="$(sy_json "$ctx" sql "SELECT id, hpath, box FROM blocks WHERE hpath='/$esc' AND type='d'")" || return $?
    if [[ "$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" len)" -gt 0 ]]; then
      echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" docs-sql
      return 0
    fi
    # b. 笔记本前缀 + 剩余路径
    if [[ "$work" == */* ]]; then
      out="$(sy_locate_nbpath "$ctx" "$work")" || return $?
      if [[ -n "$out" ]]; then
        echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" docs-sql
        return 0
      fi
    fi
    # c. 后缀匹配
    out="$(sy_locate_suffix "$ctx" "$work")" || return $?
    if [[ "$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" len)" -gt 0 ]]; then
      echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" docs-sql
      return 0
    fi
  elif [[ "$work" == */* ]]; then
    # e. 无前导 / 含 / (find 输出格式: 工作/调课): 先笔记本前缀, 再后缀
    out="$(sy_locate_nbpath "$ctx" "$work")" || return $?
    if [[ -n "$out" ]]; then
      echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" docs-sql
      return 0
    fi
    out="$(sy_locate_suffix "$ctx" "$work")" || return $?
    if [[ "$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" len)" -gt 0 ]]; then
      echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" docs-sql
      return 0
    fi
  fi
  # d/f. 标题: document search, 精确同名优先
  out="$(sy_json "$ctx" document search "$ref" |
    "$SY_NODE" "$SY_LIB_DIR/fmt.js" docs-search 1 "" "" "$ref")" || return $?
  if [[ "$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" len)" -gt 0 ]]; then
    echo "$out"
    return 0
  fi
  # g. 无 / 引用补后缀匹配 (目录名场景, 如 cat AI伴学)
  if [[ "$work" != */* ]] && [[ -n "$work" ]]; then
    out="$(sy_locate_suffix "$ctx" "$work")" || return $?
    if [[ "$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" len)" -gt 0 ]]; then
      echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" docs-sql
      return 0
    fi
  fi
  echo "$out"
}

# 笔记本前缀路径精确匹配: 第一段为笔记本名时按 box + hpath 精确
#   成功: stdout = JSON 数组; 第一段不是笔记本名: stdout 空
sy_locate_nbpath() { # <ctx> <work(无前导/)> -> stdout: JSON 数组或空
  local ctx="$1" work="$2"
  local first rest nb
  first="${work%%/*}"
  rest="${work#*/}"
  [[ "$first" == "$work" ]] && return 0
  if [[ "$first" =~ ^[0-9]{14}-[a-z0-9]{6,8}$ ]]; then
    nb="$first"
  else
    nb="$(sy_resolve_notebook_soft "$ctx" "$first")" || return $?
  fi
  [[ -n "$nb" ]] || return 0
  local esc
  esc="${rest//\'/\'\'}"
  sy_json "$ctx" sql "SELECT id, hpath, box FROM blocks WHERE box='$nb' AND hpath='/$esc' AND type='d'"
}

# 解析文档引用为唯一 doc id; 无/多匹配时报错 (多匹配时列出候选)
#   sy_resolve_doc <ctx> <引用> -> stdout: doc id
sy_resolve_doc() {
  local ctx="$1" ref="$2"
  local out
  out="$(sy_locate_docs "$ctx" "$ref")"
  local n
  n="$(echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" len)"
  if [[ "$n" -eq 0 ]]; then
    sy_die 1 "$ctx: 找不到文档 '$ref'" "用 'siyuan find $ref' 搜相近文档, 或 'siyuan ls' 看笔记本结构"
  fi
  if [[ "$n" -gt 1 ]]; then
    local names
    names="$(sy_nb_names "$ctx")" || return $?
    echo "$out" | NB_NAMES="$names" "$SY_NODE" "$SY_LIB_DIR/fmt.js" candidates >&2
    sy_die 1 "$ctx: 文档引用 '$ref' 有 $n 个匹配" "用完整路径消歧, 如 'siyuan $ctx /完整/路径/标题'"
  fi
  echo "$out" | "$SY_NODE" "$SY_LIB_DIR/fmt.js" ids
}

# 解析块引用 (块 id 或文档引用) -> stdout: block id
#   规则: id 形态 (块/文档 id) 直接返回; 标题/路径按文档引用解析,
#         文档根块 id 即文档 id (blocks 表 type=d 的 id), 直接可用
sy_resolve_block() { # <ctx> <引用>
  local ctx="$1" ref="$2"
  if [[ "$ref" =~ ^[0-9]{14}-[a-z0-9]{6,8}$ ]]; then
    echo "$ref"
    return 0
  fi
  sy_resolve_doc "$ctx" "$ref"
}

# 取文档元数据 (id -> hPath/box, 来自 blocks 表)
#   sy_doc_meta <ctx> <doc-id> -> stdout: "hPath<TAB>box"
sy_doc_meta() {
  local ctx="$1" id="$2"
  sy_json "$ctx" sql "SELECT hpath, box FROM blocks WHERE id='$id'" |
    "$SY_NODE" "$SY_LIB_DIR/fmt.js" meta || return $?
}
