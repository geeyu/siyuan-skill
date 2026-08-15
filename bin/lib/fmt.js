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
'use strict';
const fs = require('fs');

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
  return { id: r.path.split('/').pop().replace(/\.sy$/, ''), hPath: r.hPath, box: r.box };
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
    for (const d of parse()) console.log('    ' + d.id + '\t' + d.hPath + '\t' + d.box);
    break;
  case 'docs-sql':
    console.log(JSON.stringify(parse().map((r) => ({ id: r.id, hPath: r.hpath, box: r.box }))));
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
      content: (b.fcontent || '').replace(/<\/?mark>/g, ''),
    }));
    console.log(JSON.stringify(out));
    break;
  }
  case 'grep-tsv': {
    for (const b of parse().blocks || []) {
      const c = (b.fcontent || '').replace(/<\/?mark>/g, '').replace(/\n/g, ' ');
      console.log([b.rootID || '', b.hPath || '', c].join('\t'));
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
  default:
    console.error('fmt.js: unknown subcommand: ' + cmd);
    process.exit(2);
}
