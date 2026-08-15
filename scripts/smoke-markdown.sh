#!/usr/bin/env bash
# wf-w1-6 冒烟: 全命令 --markdown 输出验证 (markdown 结构合法性 + 互斥 + 管道组合)
# 只读为主; 写命令走真实工作区 (需 serve 6806), 写后即清理
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/share/fnm/node-versions/v22.22.0/installation/bin:$PATH"
S="$(pwd)/bin/siyuan"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }

DOC=20260708113326-ktl9bis

echo "== 表格类: 表头 + 分隔行 + 列匹配 =="
tbl_check() { # <名称> <列正则> <命令...>
  local name="$1" pat="$2"
  shift 2
  local out line2
  out="$("$S" "$@" 2>/dev/null)"
  line2="$(echo "$out" | sed -n 2p)"
  if [[ "$out" =~ ^\|.*\|$ ]] && [[ "$line2" == *---* ]] && echo "$out" | grep -qE "$pat"; then
    ok "$name"
  else
    bad "$name (got: $(echo "$out" | head -2 | tr '\n' ' '))"
  fi
}
tbl_check "ls --markdown" "名称.*ID" ls --markdown
tbl_check "ls 工作 --markdown" "名称.*ID.*笔记本" ls 工作 --markdown
tbl_check "sql --markdown" "hpath.*id" sql "SELECT id,hpath FROM blocks WHERE type='d' AND hpath='/调课' LIMIT 2" --markdown
tbl_check "stat --markdown" "字段.*值" stat /调课 --markdown
tbl_check "av list --markdown" "名称.*avID.*路径" av list --markdown
tbl_check "av keys --markdown" "字段名.*类型.*keyID" av keys 排查记录库 --markdown
tbl_check "av rows --markdown" "itemID.*标题" av rows 排查记录库 --limit 2 --markdown
tbl_check "av get --markdown" "项目.*值" av get 排查记录库 --row 20260816050945-270wfmd --markdown
tbl_check "av verify --markdown" "itemID.*标题" av verify 排查记录库 --markdown

echo "== 列表类: bullet 层级 + 链接 =="
list_check() { # <名称> <行号> <正则> <命令...>
  local name="$1" line="$2" pat="$3"
  shift 3
  local out l
  out="$("$S" "$@" 2>/dev/null)"
  l="$(echo "$out" | sed -n "${line}p")"
  if echo "$l" | grep -qE "$pat"; then ok "$name"; else bad "$name (line$line=[$l])"; fi
}
list_check "tree --markdown 首行 bullet" 1 '^ *- ' tree "$DOC" --markdown
list_check "tree -l --markdown 块链接" 1 'siyuan://blocks/' tree "$DOC" -l --markdown
list_check "find --markdown 文档链接" 1 'siyuan://docs/' find 调课 --markdown
list_check "grep --markdown 文档+片段嵌套" 1 'siyuan://docs/' grep --content 调课 --markdown
list_check "grep --markdown 片段缩进" 2 '^  - ' grep --content 调课 --markdown
list_check "which --markdown 键值列表" 1 '文档 ID' which /调课 --markdown
list_check "children --markdown 块链接" 1 'siyuan://blocks/' children "$DOC" --markdown

grep_l_out="$($S grep --content 调课 -l --markdown 2>/dev/null)"
if ! echo "$grep_l_out" | grep -qE '^  - '; then
  ok "grep -l --markdown 只列文档 (无片段)"
else
  bad "grep -l --markdown (含片段行)"
fi
"$S" backlinks "$DOC" --markdown >/dev/null 2>&1 && ok "backlinks --markdown 不报错" || bad "backlinks --markdown"

echo "== 片段类 (head/tail fenced) + cat 原样 =="
h1="$($S head "$DOC" -n 2 --markdown | head -1)"
h2="$($S head "$DOC" -n 2 --markdown | tail -1)"
t1="$($S tail "$DOC" -n 2 --markdown | head -1)"
[[ "$h1" == '```markdown' && "$h2" == '```' ]] && ok "head --markdown fenced" || bad "head --markdown [$h1][$h2]"
[[ "$t1" == '```markdown' ]] && ok "tail --markdown fenced" || bad "tail --markdown [$t1]"
if diff <("$S" cat "$DOC") <("$S" cat "$DOC" --markdown) >/dev/null; then ok "cat --markdown 与文本一致"; else bad "cat --markdown 与文本不一致"; fi

echo "== 写命令确认块 (需 serve 6806) =="
if curl -s -m 2 -X POST http://127.0.0.1:6806/api/system/version >/dev/null 2>&1; then
  NEW="$($S write --notebook 工作 --title "wf-w1-6冒烟" --markdown <<<'# t')"
  NID="$(echo "$NEW" | grep -oE '[0-9]{14}-[a-z0-9]{6,8}' | head -1)"
  [[ "$NEW" == *已写入文档* && "$NEW" == *siyuan://docs/* && -n "$NID" ]] \
    && ok "write --markdown 确认块" || bad "write --markdown [$NEW]"
  WJ="$($S write --notebook 工作 --title 'wf-w1-6冒烟2' --json <<<'x')"
  [[ "$WJ" == *'"id"'* ]] && ok "write --json 稳定字段" || bad "write --json [$WJ]"
  AP="$($S append "$NID" --data '## a' --markdown)"
  [[ "$AP" == *已追加文档* ]] && ok "append --markdown" || bad "append --markdown [$AP]"
  sleep 2
  BID="$($S sql "SELECT id FROM blocks WHERE root_id='$NID' AND type='h' LIMIT 1" | head -1 | cut -f1)"
  UB="$($S update-block "$BID" --data '## b' --markdown)"
  [[ "$UB" == *已更新块* ]] && ok "update-block --markdown" || bad "update-block --markdown [$UB]"
  IB="$($S insert-block --parent "$NID" --data 'p' --markdown)"
  [[ "$IB" == *已插入块* ]] && ok "insert-block --markdown" || bad "insert-block --markdown [$IB]"
  DB="$($S delete-block "$BID" --markdown)"
  [[ "$DB" == *已删除块* ]] && ok "delete-block --markdown" || bad "delete-block --markdown [$DB]"
  RD="$($S replace-doc "$NID" --data '# r' --markdown)"
  [[ "$RD" == *已替换文档* ]] && ok "replace-doc --markdown" || bad "replace-doc --markdown [$RD]"
  MV="$($S move "$NID" --parent-id 20241206145030-kemvd7v --markdown)"
  [[ "$MV" == *已移动文档* ]] && ok "move --markdown" || bad "move --markdown [$MV]"
  RM="$($S remove "$NID" --markdown)"
  if [[ "$RM" == *已删除文档* && ! "$RM" =~ ^[0-9]{14} ]]; then
    ok "remove --markdown stdout 纯净"
  else
    bad "remove --markdown [$RM]"
  fi
  NID2="$(echo "$WJ" | grep -oE '[0-9]{14}-[a-z0-9]{6,8}' | head -1)"
  "$S" remove "$NID2" >/dev/null 2>&1
else
  echo "  - serve 未运行, 写命令跳过"
fi

echo "== 互斥与契约 =="
"$S" ls --json --markdown >/dev/null 2>&1; r1=$?
"$S" ls --markdown --json >/dev/null 2>&1; r2=$?
[[ $r1 -eq 2 && $r2 -eq 2 ]] && ok "--json/--markdown 互斥 rc=2 (两种顺序)" || bad "互斥 rc=$r1/$r2"
raw_out="$($S raw --markdown notebook list 2>/dev/null | head -1)"
[[ "$raw_out" == *ID*NAME* ]] && ok "raw --markdown 原样透传" || bad "raw --markdown [$raw_out]"
md_err="$($S ls 不存在库xyz --markdown 2>&1 >/dev/null)"
md_out="$($S ls 不存在库xyz --markdown 2>/dev/null)"
[[ -n "$md_err" && -z "$md_out" ]] && ok "错误走 stderr (md 模式 stdout 空)" || bad "stderr 契约"

echo "== 管道组合 =="
pipe_line="$($S ls 工作 --markdown | $S grep 调课 --markdown | head -1)"
echo "$pipe_line" | grep -qE '^\|.*调课.*\|$' && ok "ls --markdown | grep --markdown" || bad "管道 [$pipe_line]"
"$S" find 调课 --markdown | "$S" grep 不存在词xyz --markdown >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "管道无匹配 rc=1" || bad "管道无匹配 rc=$?"

echo
echo "PASS=$PASS FAIL=$FAIL"
exit $((FAIL > 0))
