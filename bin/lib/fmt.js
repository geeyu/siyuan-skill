#!/usr/bin/env node
// siyuan — 数据格式化/转换助手 (node 统一处理内核 JSON 输出)
//
// 用法: fmt.js <子命令> [参数...]   (JSON 数据经 stdin 输入, 特殊说明除外)
// 子命令:
//   check                      校验 stdin 是合法 JSON (exit 0/2)
//   tsv <fields...>            JSON数组/对象 → TSV 行 (缺失字段留空)
//   pick <fields...>           JSON → 精简 JSON 数组 (只保留指定字段)
//   len                        JSON 数组长度
//   len-blocks                 search 响应 {blocks:[]} → blocks 长度
//   ids                        [{id,...}] → 每行 id
//   candidates                 [{id,hPath,box}] → "    id\thPath\tbox" 候选行
//   docs-sql                   blocks SQL JSON → [{id,hPath,box}] (sql 字段名 hpath)
//   docs-search <exact> <box> <limit> <ref>
//                             document search JSON → [{id,hPath,box}];
//                             exact=1 时精确同名优先; box/limit 过滤
//   meta                       blocks SQL JSON(hpath,box) → "hpath\tbox" 单行
//   first-field <f>            JSON 数组 → 第一行字段值 (空数组输出空)
//   tree-rows [long]           outline JSON → 标题树行 (按 h 层级缩进, 解 HTML 实体)
//   ls-doc-long                document list JSON → "id\tname\tN子\tsize\tmtime" 行
//   stat-text                  document get JSON → "key: value" 行
//   sql-rows [header]          sql JSON → TSV 行 (-H 加表头)
//   grep-json / grep-tsv / grep-ids   search JSON → 匹配块输出 (去 <mark>)
//   children-rows              block children JSON → "id\ttype\tcontent" 行
//   backlinks-rows             ref backlinks JSON → 递归 "id\tcontent" 行
//   cat-json <id> <hpath> <box>  stdin=markdown → {"id","hPath","box","markdown"}
//   head-json <id> <mode> <n>    stdin=截断文本 → {"id","mode","lines","markdown"}
//   http-create <host> <port> <nbid> <path>
//                             stdin=markdown → POST createDocWithMd → 新文档 id
//   http-data                  http 响应 JSON → data 字段 (code!=0 时报错 exit 1)
//
// Markdown 输出 (--markdown 模式, 框架统一路由; 笔记本名称映射走 env NB_NAMES):
//   md-table <标签:字段...>    JSON 数组 → markdown 表格 (含表头分隔行)
//   md-rows                    JSON 数组 → markdown 表格 (列 = 首行字段名)
//   md-keyval                  document get JSON → markdown 两列键值表
//   md-kv-list <标签:字段...>  JSON 数组 → markdown 键值列表 (boxName 查 NB_NAMES)
//   tree-md [long]             outline JSON → 嵌套无序列表 (h 层级缩进)
//   md-docs                    [{id,hPath,box}] → 文档 bullet (siyuan://docs 链接)
//   md-grep [listonly]         search JSON → 按文档分组 bullet + 内容片段
//   md-children                block children JSON → 块 bullet (siyuan://blocks 链接)
//   md-backlinks               反链 JSON → 递归嵌套列表
//   md-fence [lang]            stdin → fenced code block (head/tail 片段)
//   md-ok-doc <id> <标题> [动作]   写命令确认块 (文档: id+标题+链接)
//   md-ok-block <id> <动作>         写命令确认块 (块)
//   md-ok-remove <id> <标题>        删除确认块 (无链接)
//   md-ok-row <id> <动作>           数据库行确认块
//   json-ok-doc / json-ok-block / json-ok-remove / json-ok-row
//                             写命令稳定字段 JSON (id/action/link)
//
// AV (属性视图, SiYuan-Kernel 3.8.0):
//   av-search-text             database search JSON → "avID\tavName\thPath" 行 (去重)
//   av-list-md                 database search JSON → markdown 表格 (名称/avID/路径)
//   av-keys-text               database keys JSON (3.7 数组 / 3.8 对象包装兼容) → "name\ttype\tkeyID" 行
//   av-keys-rows               keys JSON → [{name,type,id}] (供 md-table)
//   av-format                  value 对象 → 展示字符串 (统一格式, 输出/验证共用)
//   av-rowcount                render JSON → view.rowCount
//   av-merge                   [render,...] JSON 数组 → 合并后的 render 对象 (翻页拼接)
//   av-build                   env SY_AV_KEYS=keys JSON, stdin=用户 values JSON
//                              → [{keyID,name,type,value,expect}] (按字段类型自动嵌套)
//   av-render <mode> [args]    stdin=render JSON; mode: rows [limit] [header] | rows-json [limit]
//                              | row <itemID> | row-json <itemID> | verify | verify-json
//                              | rows-md [limit] | row-md <itemID> | verify-md
//                              | export | find-item <title> | row-at <i> | has-row <itemID>
//                              | check-cell <itemID> <keyID> <expect>
'use strict';
const fs = require('fs');

// 管道早关 (head/管道组合) 时静默退出, 不打印 EPIPE 堆栈
process.stdout.on('error', (e) => {
  if (e && e.code === 'EPIPE') process.exit(0);
  throw e;
});

const stdin = fs.readFileSync(0, 'utf8');
const cmd = process.argv[2];
const args = process.argv.slice(3);

function parse() {
  try { return JSON.parse(stdin); } catch (e) { process.exit(2); }
}
function rowsOf(d) { return Array.isArray(d) ? d : [d]; }
function cell(r, f) {
  const v = r[f];
  return (v === null || v === undefined) ? '' : String(v);
}
function tsv(r, fields) { return fields.map((f) => cell(r, f)).join('\t'); }
function unescapeHtml(s) {
  return String(s)
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}
function docFromSearch(r) {
  const box = r.box || '';
  return { id: r.path.split('/').pop().replace(/\.sy$/, ''), hPath: fullDocPath(r.hPath, box), box };
}
// markdown 单元格转义 (| → \|, 换行 → 空格)
function escCell(v) {
  return String(v ?? '').replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
}
// md 渲染: 笔记本 id → 名称 (env NB_NAMES="id<TAB>name" 多行; 查不到原样返回 id)
function nbName(box) {
  if (!process.env.NB_NAMES || !box) return box || '';
  for (const line of process.env.NB_NAMES.split('\n')) {
    const t = line.split('\t');
    if (t[0] === box) return t.slice(1).join('\t');
  }
  return box;
}
// 完整文档路径: 「/笔记本名 + hPath」(带前导 /, 绝对路径直觉; 与输入格式双向一致)
function fullDocPath(hPath, box) {
  const hp = (hPath || '').replace(/^\//, '');
  const name = nbName(box || '');
  const base = name && name !== box ? name : '';
  const p = base ? (hp ? base + '/' + hp : base) : hp;
  return p ? '/' + p : '/';
}

switch (cmd) {
  case 'check':
    parse();
    break;
  case 'tsv': {
    const fields = args;
    for (const r of rowsOf(parse())) console.log(tsv(r, fields));
    break;
  }
  case 'pick': {
    const fields = args;
    const out = rowsOf(parse()).map((r) => {
      const o = {};
      for (const f of fields) o[f] = r[f] ?? null;
      return o;
    });
    console.log(JSON.stringify(out));
    break;
  }
  case 'len':
    console.log(rowsOf(parse()).length);
    break;
  case 'len-blocks':
    console.log((parse().blocks || []).length);
    break;
  case 'ids':
    for (const d of parse()) console.log(d.id);
    break;
  case 'candidates':
    for (const d of parse()) console.log('    ' + d.id + '\t' + fullDocPath(d.hPath, d.box) + '\t' + d.box);
    break;
  case 'docs-sql':
    console.log(JSON.stringify(parse().map((r) => ({ id: r.id, hPath: fullDocPath(r.hpath, r.box), box: r.box }))));
    break;
  case 'docs-search': {
    const exact = args[0] === '1';
    const boxFilter = args[1] || null;
    const limit = args[2] ? parseInt(args[2], 10) : null;
    const ref = args[3];
    let docs = parse().map(docFromSearch);
    if (boxFilter) docs = docs.filter((d) => d.box === boxFilter);
    if (exact) {
      const exactDocs = docs.filter((d) => d.hPath.split('/').pop() === ref);
      if (exactDocs.length) docs = exactDocs;
    }
    if (limit) docs = docs.slice(0, limit);
    console.log(JSON.stringify(docs));
    break;
  }
  case 'extract-json': {
    // 从混合输出中提取第一个 JSON 值 (内核部分命令 JSON 后有摘要文本)
    const s = stdin.trim();
    let i = 0;
    while (i < s.length && s[i] !== '{' && s[i] !== '[') i++;
    if (i >= s.length) process.exit(2);
    const open = s[i];
    const close = open === '{' ? '}' : ']';
    let depth = 0, inStr = false, j = i;
    for (; j < s.length; j++) {
      const c = s[j];
      if (inStr) {
        if (c === '\\') { j++; continue; }
        if (c === '"') inStr = false;
        continue;
      }
      if (c === '"') { inStr = true; continue; }
      if (c === open) depth++;
      else if (c === close) {
        depth--;
        if (depth === 0) { j++; break; }
      }
    }
    try {
      console.log(JSON.stringify(JSON.parse(s.slice(i, j))));
    } catch (e) { process.exit(2); }
    break;
  }
  case 'md-table': {
    // JSON 数组 → markdown 表格; 参数 "显示名:字段名" 或 "字段名"
    const cols = args.map((a) => {
      const i = a.indexOf(':');
      return i > 0 ? { label: a.slice(0, i), field: a.slice(i + 1) } : { label: a, field: a };
    });
    const rows = parse();
    if (!rows.length) { console.log('(空)'); break; }
    const esc = (v) => String(v ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ');
    console.log('| ' + cols.map((c) => c.label).join(' | ') + ' |');
    console.log('|' + cols.map(() => ' --- ').join('|') + '|');
    for (const r of rows) {
      console.log('| ' + cols.map((c) => esc(r[c.field])).join(' | ') + ' |');
    }
    break;
  }
  case 'md-keyval': {
    // document get JSON → markdown 两列表格 (字段 | 值)
    const d = parse();
    const ial = d.ial || {};
    const esc = (v) => String(v ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ');
    const lines = [];
    for (const k of ['id', 'box', 'hPath', 'path', 'parentID', 'rootID']) lines.push([k, d[k] ?? '']);
    lines.push(['title', ial.title ?? '']);
    lines.push(['content', d.content ?? '']);
    for (const k of ['icon', 'updated']) if (ial[k]) lines.push([k, ial[k]]);
    if (d.name) lines.push(['name', d.name]);
    if (d.alias) lines.push(['alias', d.alias]);
    console.log('| 字段 | 值 |');
    console.log('| --- | --- |');
    for (const [k, v] of lines) console.log('| ' + k + ' | ' + esc(v) + ' |');
    break;
  }
  case 'meta': {
    const d = parse();
    console.log(d.length ? d[0].hpath + '\t' + d[0].box : '\t');
    break;
  }
  case 'first-field': {
    const d = parse();
    console.log(d.length ? (d[0][args[0]] ?? '') : '');
    break;
  }
  case 'find-by-field': {
    const [field, value, outField] = args;
    for (const r of parse()) {
      if (String(r[field] ?? '') === value) {
        console.log(r[outField] ?? '');
        process.exit(0);
      }
    }
    break;
  }
  case 'tree-rows': {
    const long = args[0] === 'long';
    for (const x of parse()) {
      const st = x.subType || '';
      const lvl = (st.length > 1 && st[0] === 'h') ? parseInt(st.slice(1), 10) : 1;
      const name = unescapeHtml(x.name || '');
      const pad = '  '.repeat(Math.max(0, lvl - 1));
      console.log(long ? pad + name + '\t' + (x.id || '') : pad + name);
    }
    break;
  }
  case 'ls-doc-long': {
    for (const x of parse()) {
      console.log([x.id, x.name, (x.subFileCount ?? 0) + '子', x.hSize ?? '', x.hMtime ?? ''].join('\t'));
    }
    break;
  }
  case 'stat-text': {
    const d = parse();
    const ial = d.ial || {};
    for (const k of ['id', 'box', 'hPath', 'path', 'parentID', 'rootID']) {
      console.log(k + ': ' + (d[k] ?? ''));
    }
    console.log('title: ' + (ial.title ?? ''));
    console.log('content: ' + (d.content ?? ''));
    for (const k of ['icon', 'updated']) if (ial[k]) console.log(k + ': ' + ial[k]);
    if (d.name) console.log('name: ' + d.name);
    if (d.alias) console.log('alias: ' + d.alias);
    break;
  }
  case 'sql-rows': {
    const header = args[0] === 'header';
    const d = parse();
    if (!d.length) break;
    const fields = Object.keys(d[0]);
    if (header) console.log(fields.join('\t'));
    for (const r of d) console.log(fields.map((f) => cell(r, f)).join('\t'));
    break;
  }
  case 'grep-json': {
    const out = (parse().blocks || []).map((b) => ({
      rootID: b.rootID || '',
      blockID: b.id || '',
      hPath: b.hPath || '',
      fullPath: fullDocPath(b.hPath, b.box),
      content: (b.fcontent || '').replace(/<\/?mark>/g, ''),
    }));
    console.log(JSON.stringify(out));
    break;
  }
  case 'grep-tsv': {
    for (const b of parse().blocks || []) {
      const c = (b.fcontent || '').replace(/<\/?mark>/g, '').replace(/\n/g, ' ');
      console.log([b.rootID || '', fullDocPath(b.hPath, b.box), c].join('\t'));
    }
    break;
  }
  case 'grep-ids': {
    const seen = new Set();
    for (const b of parse().blocks || []) {
      const rid = b.rootID || '';
      if (rid && !seen.has(rid)) { seen.add(rid); console.log(rid); }
    }
    break;
  }
  case 'children-rows': {
    for (const b of parse()) {
      if (b && typeof b === 'object' && b.id) {
        console.log([b.id || '', b.type || '', String(b.content || '').slice(0, 60)].join('\t'));
      }
    }
    break;
  }
  case 'backlinks-rows': {
    const walk = (o) => {
      if (Array.isArray(o)) { o.forEach(walk); return; }
      if (o && typeof o === 'object') {
        if (o.content !== undefined && o.id) {
          console.log([o.id, String(o.content).slice(0, 60)].join('\t'));
        }
        for (const v of Object.values(o)) walk(v);
      }
    };
    walk(parse());
    break;
  }
  case 'cat-json':
    console.log(JSON.stringify({ id: args[0], hPath: args[1], box: args[2], markdown: stdin }));
    break;
  case 'head-json':
    console.log(JSON.stringify({ id: args[0], mode: args[1], lines: args[2], markdown: stdin }));
    break;
  case 'md-rows': {
    // JSON 数组 → markdown 表格 (列 = 首行字段名, 含表头分隔行); 空数组无输出
    const d = parse();
    if (!d.length) break;
    const fields = Object.keys(d[0]);
    console.log('| ' + fields.join(' | ') + ' |');
    console.log('|' + fields.map(() => ' --- ').join('|') + '|');
    for (const r of d) console.log('| ' + fields.map((f) => escCell(r[f])).join(' | ') + ' |');
    break;
  }
  case 'md-kv-list': {
    // JSON 数组 → markdown 键值列表 ("- 标签: `值`" 每对象 N 行, 对象间空行)
    //   字段 "boxName" 特殊: 从 r.box 查笔记本名称 (env NB_NAMES)
    const cols = args.map((a) => {
      const i = a.indexOf(':');
      return i > 0 ? { label: a.slice(0, i), field: a.slice(i + 1) } : { label: a, field: a };
    });
    const rows = parse();
    rows.forEach((r, idx) => {
      if (idx > 0) console.log('');
      for (const c of cols) {
        const raw = c.field === 'boxName' ? nbName(r.box) : r[c.field];
        console.log('- ' + c.label + ': `' + String(raw ?? '').replace(/`/g, "'") + '`');
      }
    });
    break;
  }
  case 'tree-md': {
    // outline JSON → 嵌套无序列表 (h 层级 → 2 空格缩进); long 附块 id 链接
    const long = args[0] === 'long';
    for (const x of parse()) {
      const st = x.subType || '';
      const lvl = (st.length > 1 && st[0] === 'h') ? parseInt(st.slice(1), 10) : 1;
      const name = unescapeHtml(x.name || '');
      let line = '  '.repeat(Math.max(0, lvl - 1)) + '- ' + name;
      if (long && x.id) line += ' ([`' + x.id + '`](siyuan://blocks/' + x.id + '))';
      console.log(line);
    }
    break;
  }
  case 'md-docs': {
    // [{id,hPath,box}] → "- [标题](siyuan://docs/<id>) — `hPath` · 笔记本 `名称`"
    for (const d of parse()) {
      const title = (d.hPath || '').split('/').filter(Boolean).pop() || d.id;
      console.log('- [' + title + '](siyuan://docs/' + d.id + ') — `' + (d.hPath || '') + '` · 笔记本 `' + nbName(d.box) + '`');
    }
    break;
  }
  case 'md-ls-docs': {
    // document list JSON → markdown 表格 (env NB_NAME=笔记本名); [long] 附子文档/大小/时间
    const long = args[0] === 'long';
    const nb = process.env.NB_NAME || '';
    const rows = parse();
    if (!rows.length) break;
    const header = long ? ['名称', 'ID', '笔记本', '子文档', '大小', '修改时间'] : ['名称', 'ID', '笔记本'];
    console.log('| ' + header.join(' | ') + ' |');
    console.log('|' + header.map(() => ' --- ').join('|') + '|');
    for (const x of rows) {
      const line = long
        ? [x.name ?? '', x.id ?? '', nb, x.subFileCount ?? 0, x.hSize ?? '', x.hMtime ?? '']
        : [x.name ?? '', x.id ?? '', nb];
      console.log('| ' + line.map(escCell).join(' | ') + ' |');
    }
    break;
  }
  case 'md-grep': {
    // search JSON {blocks:[]} → 按文档分组: 文档 bullet + 内容片段嵌套 bullet
    //   [listonly] 只列文档 (等价 -l)
    const listonly = args[0] === 'listonly';
    const groups = new Map();
    for (const b of parse().blocks || []) {
      const rid = b.rootID || b.id;
      if (!groups.has(rid)) groups.set(rid, { hPath: b.hPath || '', box: b.box || '', items: [] });
      if (!listonly) {
        const c = String(b.fcontent || '').replace(/<\/?mark>/g, '').replace(/\s*\n\s*/g, ' ').trim();
        if (c) groups.get(rid).items.push(c);
      }
    }
    for (const [rid, g] of groups) {
      const title = g.hPath.split('/').filter(Boolean).pop() || rid;
      console.log('- [' + title + '](siyuan://docs/' + rid + ') — `' + g.hPath + '` · 笔记本 `' + nbName(g.box) + '`');
      for (const c of g.items) console.log('  - ' + c.slice(0, 120));
    }
    break;
  }
  case 'md-children': {
    // block children JSON → "- `type` 内容片段 ([id](siyuan://blocks/<id>))"
    for (const b of parse()) {
      if (b && typeof b === 'object' && b.id) {
        const c = String(b.content || '').replace(/\n/g, ' ').slice(0, 60);
        console.log('- `' + (b.type || '') + '` ' + c + ' ([`' + b.id + '`](siyuan://blocks/' + b.id + '))');
      }
    }
    break;
  }
  case 'md-backlinks': {
    // 反链 JSON → 递归嵌套列表 (内容 bullet, 子反链缩进)
    const walk = (o, depth) => {
      if (Array.isArray(o)) { o.forEach((x) => walk(x, depth)); return; }
      if (o && typeof o === 'object') {
        if (o.content !== undefined && o.id) {
          const c = String(o.content).replace(/\n/g, ' ').slice(0, 60);
          console.log('  '.repeat(depth) + '- ' + c + ' ([`' + o.id + '`](siyuan://blocks/' + o.id + '))');
          depth += 1;
        }
        for (const v of Object.values(o)) walk(v, depth);
      }
    };
    walk(parse(), 0);
    break;
  }
  case 'md-fence': {
    // stdin → fenced code block (head/tail 片段标记; 原样包裹)
    const lang = args[0] || '';
    console.log('```' + lang);
    process.stdout.write(stdin.replace(/\n+$/, '') + '\n```\n');
    break;
  }
  case 'md-ok-doc': {
    // <id> <标题> [动作] → 文档写入确认块 (blockquote: 标题链接 + 文档 ID)
    const [id, title, verb] = args;
    console.log('> ✅ 已' + (verb || '写入') + '文档 [' + (title || id) + '](siyuan://docs/' + id + ')');
    console.log('> - 文档 ID: `' + id + '`');
    console.log('> - 标题: ' + (title || ''));
    break;
  }
  case 'md-ok-block': {
    // <id> <动作> → 块写入确认块
    const [id, verb] = args;
    console.log('> ✅ 已' + (verb || '操作') + '块 [' + id + '](siyuan://blocks/' + id + ')');
    break;
  }
  case 'md-ok-remove': {
    // <id> <标题> → 文档删除确认块 (无链接)
    const [id, title] = args;
    console.log('> ✅ 已删除文档 ' + (title || id) + ' (`' + id + '`)');
    break;
  }
  case 'md-ok-row': {
    // <id> <动作> → 数据库行确认块
    const [id, verb] = args;
    console.log('> ✅ 已' + (verb || '操作') + '行 `' + id + '`');
    break;
  }
  case 'json-ok-doc': {
    // <id> <标题> [动作] → 写命令稳定字段 {id,title,link[,action]}
    const [id, title, action] = args;
    const o = { id, title: title || '', link: 'siyuan://docs/' + id };
    if (action) o.action = action;
    console.log(JSON.stringify(o));
    break;
  }
  case 'json-ok-block': {
    // <id> <动作> → 块操作稳定字段 {id,action,link}
    const [id, action] = args;
    console.log(JSON.stringify({ id, action: action || '', link: 'siyuan://blocks/' + id }));
    break;
  }
  case 'json-ok-remove': {
    // <id> <标题> → 删除稳定字段 {id,title,action}
    const [id, title] = args;
    console.log(JSON.stringify({ id, title: title || '', action: 'remove' }));
    break;
  }
  case 'json-ok-row': {
    // <id> <动作> → 数据库行稳定字段 {id,action}
    const [id, action] = args;
    console.log(JSON.stringify({ id, action: action || '' }));
    break;
  }
  case 'http-create': {
    const [host, port, nbid, path] = args;
    const body = JSON.stringify({ notebook: nbid, path, markdown: stdin });
    fetch(`http://${host}:${port}/api/filetree/createDocWithMd`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
      signal: AbortSignal.timeout(10000),
    })
      .then((r) => r.json())
      .then((d) => { process.stdout.write(String(d.data || '')); })
      .catch(() => process.exit(1));
    break;
  }
  case 'http-data': {
    const d = parse();
    if (d.code === 0) {
      const data = d.data;
      process.stdout.write(typeof data === 'string' ? data : (data || ''));
    } else {
      console.error('Error: ' + (d.msg || 'unknown'));
      process.exit(1);
    }
    break;
  }
  case 'idx': { // JSON 数组 → 第 i 项 (原始 JSON)
    const i = parseInt(args[0], 10);
    const d = parse();
    if (d[i] !== undefined) console.log(JSON.stringify(d[i]));
    break;
  }
  case 'field': { // JSON 对象 → 字段字符串值
    const d = parse();
    const v = d[args[0]];
    console.log(v === undefined || v === null ? '' : String(v));
    break;
  }
  case 'field-json': { // JSON 对象 → 字段原始 JSON
    const d = parse();
    if (d[args[0]] !== undefined) console.log(JSON.stringify(d[args[0]]));
    break;
  }
  // ===== AV (属性视图) 3.8.0 支持 =====
  case 'av-search-text': {
    const seen = new Set();
    for (const d of parse()) {
      if (seen.has(d.avID)) continue;
      seen.add(d.avID);
      console.log([d.avID, d.avName, d.hPath || ''].join('\t'));
    }
    break;
  }
  case 'av-list-md': {
    // database search JSON → markdown 表格 (按 avID 去重): 名称 | avID | 路径
    const seen = new Set();
    const rows = [];
    for (const d of parse()) {
      if (seen.has(d.avID)) continue;
      seen.add(d.avID);
      rows.push([d.avName ?? '', d.avID ?? '', d.hPath ?? '']);
    }
    if (!rows.length) break;
    console.log('| 名称 | avID | 路径 |');
    console.log('| --- | --- | --- |');
    for (const r of rows) console.log('| ' + r.map(escCell).join(' | ') + ' |');
    break;
  }
  case 'av-keys-rows': {
    // keys JSON (3.8 {id,name,keys:[]} 或旧数组) → [{name,type,id}] (供 md-table)
    const d = parse();
    const keys = Array.isArray(d) ? d : (d.keys || []);
    console.log(JSON.stringify(keys.map((k) => ({ name: k.name ?? '', type: k.type ?? '', id: k.id ?? '' }))));
    break;
  }
  case 'av-keys-text': {
    const d = parse();
    const keys = Array.isArray(d) ? d : (d.keys || []); // B1: 3.8 为 {id,name,keys:[]}
    for (const k of keys) console.log([k.name, k.type, k.id].join('\t'));
    break;
  }
  case 'av-format':
    console.log(avFormatValue(parse()));
    break;
  case 'av-rowcount':
    console.log((parse().view || {}).rowCount || 0);
    break;
  case 'av-merge': {
    const pages = parse();
    const first = pages[0];
    if (!first) break;
    const rows = [];
    for (const p of pages) rows.push(...(((p.view) || {}).rows || []));
    console.log(JSON.stringify({
      id: first.id,
      name: first.name,
      viewID: first.viewID,
      viewType: first.viewType,
      page: 1,
      pageSize: rows.length,
      view: Object.assign({}, first.view || {}, { rows, rowCount: (first.view || {}).rowCount || rows.length }),
    }));
    break;
  }
  case 'av-build': {
    // env SY_AV_KEYS=keys JSON; stdin=用户 values {字段名或keyID: 简单值|完整value对象}
    let keysRaw;
    try {
      keysRaw = JSON.parse(process.env.SY_AV_KEYS || '[]');
    } catch (e) {
      console.error('av-build: SY_AV_KEYS 不是合法 JSON');
      process.exit(1);
    }
    const keys = Array.isArray(keysRaw) ? keysRaw : (keysRaw.keys || []);
    const values = parse();
    if (!values || typeof values !== 'object' || Array.isArray(values)) {
      console.error('av-build: --values 必须是 JSON 对象 {字段名: 值}');
      process.exit(1);
    }
    const byId = new Map(keys.map((k) => [k.id, k]));
    const out = [];
    for (const [ref, v] of Object.entries(values)) {
      const k = byId.get(ref) || keys.find((x) => x.name === ref);
      if (!k) {
        console.error('av-build: 找不到字段 "' + ref + '", 可用: ' + keys.map((x) => x.name).join(', '));
        process.exit(1);
      }
      if (k.type === 'block') {
        console.error('av-build: 忽略 block 字段 "' + k.name + '" (由 --content/--block 设置)');
        continue;
      }
      const built = avBuildValue(k, v);
      if (!built) {
        console.error('av-build: 字段 "' + k.name + '" 类型 ' + k.type + ' 不支持写入 (只读/特殊字段)');
        process.exit(1);
      }
      out.push({ keyID: k.id, name: k.name, type: k.type, value: built.value, expect: built.expect });
    }
    console.log(JSON.stringify(out));
    break;
  }
  case 'av-render':
    avRenderMode(parse(), args[0] || '', args.slice(1));
    break;
  default:
    console.error('fmt.js: unknown subcommand: ' + cmd);
    process.exit(2);
}

// ===== AV (属性视图) 辅助 =====

// value 对象 → 展示字符串 (输出/验证共用的唯一格式)
function avFormatValue(v) {
  if (!v || typeof v !== 'object') return String(v ?? '');
  const t = v.type || v.valueType || '';
  if (t === 'block') return String((v.block || {}).content ?? '');
  if (t === 'text') return String((v.text || {}).content ?? '');
  if (t === 'url' || t === 'email' || t === 'phone') return String((v[t] || {}).content ?? '');
  if (t === 'date') {
    const d = v.date || {};
    const f = d.formattedContent;
    return f !== undefined && f !== null && f !== '' ? String(f) : String(d.content ?? '');
  }
  if (t === 'select' || t === 'mSelect') return (v.mSelect || []).map((c) => String(c.content ?? '')).join(',');
  if (t === 'checkbox') return (v.checkbox || {}).checked ? '✓' : '✗';
  if (t === 'template') return String((v.template || {}).content ?? '');
  if (t === 'number') {
    const n = v.number || {};
    return String(n.content ?? (n.formattedContent ?? ''));
  }
  if (t === 'relation') return ((v.relation || {}).blockIDs || []).join(',');
  if (t === 'mAsset') return (v.mAsset || []).map((a) => a.name || a.content || '').join(',');
  return JSON.stringify(v).slice(0, 200);
}

// 用户简单值 → 按字段类型嵌套的 value 对象 (+ 期望展示值 expect, 用于写入后验证)
// 返回 {value, expect} 或 null (类型不可写)
function avBuildValue(k, v) {
  const t = k.type;
  // 完整 value 对象直接透传 (带 type 字段, 调用方自行保证嵌套正确)
  if (v && typeof v === 'object' && !Array.isArray(v) && v.type) {
    return { value: v, expect: avFormatValue(v) };
  }
  const list = () => (Array.isArray(v) ? v.map(String) : String(v).split(',').map((s) => s.trim()).filter(Boolean));
  switch (t) {
    case 'text':
      return { value: { type: 'text', text: { content: String(v) } }, expect: String(v) };
    case 'url':
      return { value: { type: 'url', url: { content: String(v) } }, expect: String(v) };
    case 'email':
      return { value: { type: 'email', email: { content: String(v) } }, expect: String(v) };
    case 'phone':
      return { value: { type: 'phone', phone: { content: String(v) } }, expect: String(v) };
    case 'template':
      return { value: { type: 'template', template: { content: String(v) } }, expect: String(v) };
    case 'date': {
      let ms;
      if (typeof v === 'number') ms = v;
      else if (typeof v === 'string' && /^\d+$/.test(v.trim())) ms = parseInt(v.trim(), 10);
      else {
        const s = String(v).trim();
        ms = Date.parse(/^\d{4}-\d{2}-\d{2}$/.test(s) ? s + 'T00:00:00Z' : s);
        if (Number.isNaN(ms)) {
          console.error('av-build: 字段 "' + k.name + '" 日期无法解析: ' + v);
          process.exit(1);
        }
      }
      return { value: { type: 'date', date: { content: ms, isNotEmpty: true } }, expect: String(ms) };
    }
    case 'select': {
      const one = Array.isArray(v) ? String(v[0]) : String(v);
      if (!one.trim()) {
        console.error('av-build: 字段 "' + k.name + '" select 值不能为空');
        process.exit(1);
      }
      return { value: { type: 'select', mSelect: [{ content: one }] }, expect: one };
    }
    case 'mSelect': {
      const opts = list();
      return { value: { type: 'mSelect', mSelect: opts.map((c) => ({ content: c })) }, expect: opts.join(',') };
    }
    case 'checkbox': {
      const b = typeof v === 'boolean' ? v : (v === 'true' || v === '1' || v === '✓');
      return { value: { type: 'checkbox', checkbox: { checked: b } }, expect: b ? '✓' : '✗' };
    }
    case 'number': {
      const n = Number(v);
      if (Number.isNaN(n)) {
        console.error('av-build: 字段 "' + k.name + '" 数字无法解析: ' + v);
        process.exit(1);
      }
      return { value: { type: 'number', number: { content: n, isNotEmpty: true } }, expect: String(n) };
    }
    case 'relation': {
      const ids = list();
      return { value: { type: 'relation', relation: { blockIDs: ids } }, expect: ids.join(',') };
    }
    case 'mAsset': {
      const names = list();
      const items = names.map((s) => ({ type: 'file', name: s, content: '' }));
      return { value: { type: 'mAsset', mAsset: items }, expect: items.map((a) => a.name).join(',') };
    }
    default:
      return null; // rollup/created/updated/lineNumber/block 等只读/特殊字段
  }
}

// render JSON → 各类行数据输出 (B2: 行数据唯一来源)
function avRenderMode(d, mode, args) {
  const v = d.view || {};
  const columns = v.columns || [];
  const rows = v.rows || [];
  const visCols = columns.filter((c) => !c.hidden);
  const rowOf = (r) => {
    const cells = {};
    let title = '';
    for (const c of r.cells || []) {
      const val = c.value || {};
      cells[val.keyID] = val;
      if ((val.type || '') === 'block') title = String((val.block || {}).content ?? '');
    }
    const fields = {};
    for (const col of visCols) {
      if (col.type === 'block') continue;
      fields[col.name] = avFormatValue(cells[col.id]);
    }
    return { itemID: r.id, title, fields };
  };
  const docIDOf = (r) => {
    for (const c of r.cells || []) {
      const val = c.value || {};
      if ((val.type || '') === 'block') return String((val.block || {}).id ?? '');
    }
    return '';
  };
  const lineOf = (o) => {
    const line = [o.itemID, o.title];
    for (const col of visCols) if (col.type !== 'block') line.push(o.fields[col.name] ?? '');
    return line.join('\t');
  };
  const headerOf = () => {
    const line = ['itemID', '标题'];
    for (const col of visCols) if (col.type !== 'block') line.push(col.name);
    return line.join('\t');
  };
  const printRow = (r) => {
    const o = rowOf(r);
    console.log('■ ' + (o.title || '(无标题)') + ' (' + o.itemID + ')');
    for (const col of visCols) {
      if (col.type === 'block') continue;
      console.log('  ' + col.name.padEnd(10) + ' (' + col.type.padEnd(7) + ') | ' + (o.fields[col.name] ?? ''));
    }
  };
  switch (mode) {
    case 'rows': {
      const limit = args[0] ? parseInt(args[0], 10) : 0;
      const header = args[1] === '1';
      const list = limit > 0 ? rows.slice(0, limit) : rows;
      if (header) console.log(headerOf());
      for (const r of list) console.log(lineOf(rowOf(r)));
      break;
    }
    case 'rows-json': {
      const limit = args[0] ? parseInt(args[0], 10) : 0;
      const list = limit > 0 ? rows.slice(0, limit) : rows;
      console.log(JSON.stringify(list.map((r) => rowOf(r))));
      break;
    }
    case 'row': {
      const r = rows.find((x) => x.id === args[0]);
      if (!r) {
        console.error('av: 找不到行 ' + args[0]);
        process.exit(1);
      }
      printRow(r);
      break;
    }
    case 'row-json': {
      const r = rows.find((x) => x.id === args[0]);
      if (!r) {
        console.error('av: 找不到行 ' + args[0]);
        process.exit(1);
      }
      console.log(JSON.stringify(rowOf(r)));
      break;
    }
    case 'rows-md': {
      // markdown 表格: itemID | 标题 | 各字段 (列 = 可见字段)
      const limit = args[0] ? parseInt(args[0], 10) : 0;
      const list = limit > 0 ? rows.slice(0, limit) : rows;
      const objs = list.map((r) => rowOf(r));
      if (!objs.length) break;
      const header = ['itemID', '标题'];
      for (const col of visCols) if (col.type !== 'block') header.push(col.name);
      console.log('| ' + header.join(' | ') + ' |');
      console.log('|' + header.map(() => ' --- ').join('|') + '|');
      for (const o of objs) {
        const line = [o.itemID, o.title];
        for (const col of visCols) if (col.type !== 'block') line.push(o.fields[col.name] ?? '');
        console.log('| ' + line.map(escCell).join(' | ') + ' |');
      }
      break;
    }
    case 'row-md': {
      // markdown 键值表: 项目 | 值 (行 ID/标题/每字段)
      const r = rows.find((x) => x.id === args[0]);
      if (!r) {
        console.error('av: 找不到行 ' + args[0]);
        process.exit(1);
      }
      const o = rowOf(r);
      console.log('| 项目 | 值 |');
      console.log('| --- | --- |');
      console.log('| 行 ID | `' + o.itemID + '` |');
      console.log('| 标题 | ' + escCell(o.title || '(无标题)') + ' |');
      for (const col of visCols) {
        if (col.type === 'block') continue;
        console.log('| ' + escCell(col.name) + ' | ' + escCell(o.fields[col.name] ?? '') + ' |');
      }
      break;
    }
    case 'verify-md':
      avRenderMode(d, 'rows-md', ['0']);
      break;
    case 'verify':
      for (const r of rows) printRow(r);
      break;
    case 'verify-json':
      console.log(JSON.stringify(rows.map((r) => rowOf(r))));
      break;
    case 'export': {
      const out = rows.map((r) => Object.assign({ docID: docIDOf(r) }, rowOf(r)));
      console.log(JSON.stringify(out, null, 2));
      break;
    }
    case 'find-item': {
      const title = args[0] ?? '';
      let found = '';
      for (const r of rows) {
        for (const c of r.cells || []) {
          const val = c.value || {};
          if ((val.type || '') === 'block' && String((val.block || {}).content ?? '') === title) found = r.id;
        }
      }
      if (found) console.log(found);
      break;
    }
    case 'find-item-by-doc': {
      // 绑定文档块的行: block cell 的 block.id == docID (绑定后标题被文档标题覆盖, 不能按标题匹配)
      const docID = args[0] ?? '';
      let found = '';
      for (const r of rows) {
        for (const c of r.cells || []) {
          const val = c.value || {};
          if ((val.type || '') === 'block' && String((val.block || {}).id ?? '') === docID) found = r.id;
        }
      }
      if (found) console.log(found);
      break;
    }
    case 'row-at': {
      const i = parseInt(args[0], 10);
      const r = rows[i];
      if (r) console.log(r.id);
      break;
    }
    case 'has-row':
      console.log(rows.some((x) => x.id === args[0]) ? 'ok' : 'none');
      break;
    case 'check-cell': {
      const [itemID, keyID, expect] = args;
      const r = rows.find((x) => x.id === itemID);
      if (!r) {
        console.log('FAIL\t行不存在');
        break;
      }
      const cell = (r.cells || []).find((c) => (c.value || {}).keyID === keyID);
      if (!cell || !cell.value) {
        console.log('FAIL\t单元格为空');
        break;
      }
      const val = cell.value;
      let actual;
      let ok;
      if (val.type === 'date') {
        // date 用毫秒 content 比较 (formattedContent 受时区影响)
        const got = (val.date || {}).content;
        actual = got === undefined ? '' : String(got);
        ok = actual === expect;
      } else {
        actual = avFormatValue(val);
        ok = actual === expect;
      }
      console.log((ok ? 'ok' : 'FAIL') + '\t' + actual);
      break;
    }
    default:
      console.error('fmt.js av-render: 未知模式 ' + mode);
      process.exit(2);
  }
}
