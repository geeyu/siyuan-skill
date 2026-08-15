#!/usr/bin/env node
/**
 * siyuan AV (数据库) 操作工具库
 *
 * 用法:
 *   const av = require('./av_ops.js');
 *   const avID = av.search('排查记录');
 *   const keys = av.listKeys(avID);
 *   const itemId = av.addRow(avID, docId, '标题');
 *   av.setCell(avID, keyId, itemId, { type:'select', mSelect:[{content:'调课调讲'}] });
 *   av.setCellText(avID, keyId, itemId, '含"引号"的内容');  // 便捷方法
 *   av.verify(avID);  // 打印所有行字段值
 *
 * 设计要点:
 *   1. value 用临时文件传递, 避免 shell 引号转义陷阱 (思源 CLI --value 对含双引号的 JSON 极易静默失败)
 *   2. item add 不返回 itemID, 提供 findItemIdByDoc 反查
 *   3. setCell 自动按类型构造正确嵌套结构 (text/url/date/select/mSelect/checkbox/template)
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const SIYUAN = process.env.SIYUAN_BIN || path.join(__dirname, '..', 'bin', 'siyuan');
const TMP_VAL = path.join(os.tmpdir(), 'siyuan_av_val.json');

function run(cmd, opts = {}) {
  try {
    return execSync(cmd, { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'], ...opts });
  } catch (e) {
    return 'ERR: ' + (e.stderr || e.stdout || e.message || '').toString().slice(0, 200);
  }
}

/** 执行 SQL, 返回数组 */
function sql(stmt) {
  const out = run(`${SIYUAN} sql "${stmt.replace(/"/g, '\\"')}" 2>/dev/null`);
  try { return JSON.parse(out); } catch (e) { return []; }
}

/** 按名称搜索数据库, 返回 avID */
function search(name) {
  const out = run(`${SIYUAN} raw database search "${name}" -f json 2>/dev/null`);
  const data = JSON.parse(out);
  if (!data || !data.length) throw new Error(`找不到名为 "${name}" 的数据库`);
  return data[0].avID;
}

/** 列出数据库所有字段, 返回 [{id, name, type}] */
function listKeys(avID) {
  const out = run(`${SIYUAN} raw database keys --av ${avID} -f json 2>/dev/null`);
  return JSON.parse(out);
}

/** 按 name 查 keyID */
function keyId(avID, name) {
  const keys = listKeys(avID);
  const k = keys.find(k => k.name === name);
  if (!k) throw new Error(`找不到字段 "${name}", 可用: ${keys.map(k => k.name).join(', ')}`);
  return k.id;
}

/**
 * 给数据库加一行, 绑定文档块
 * @returns itemID (行ID, 不等于 blockID, 自动反查)
 */
function addRow(avID, docBlockId, content) {
  run(`${SIYUAN} raw database item add --av ${avID} --block ${docBlockId} --content "${(content || '').replace(/"/g, '\\"')}" -f json 2>&1`);
  return findItemIdByDoc(avID, docBlockId);
}

/** 新增游离行 (不绑定文档), 返回 itemID */
function addDetachedRow(avID, content) {
  run(`${SIYUAN} raw database item add --av ${avID} --detached --content "${(content || '').replace(/"/g, '\\"')}" -f json 2>&1`);
  // detached 行也需反查, 取最后一行的 blockID
  const data = get(avID);
  const blockKv = data.keyValues.find(kv => kv.key.type === 'block');
  if (!blockKv || !blockKv.values.length) throw new Error('无法反查 itemID');
  return blockKv.values[blockKv.values.length - 1].blockID;
}

/** 根据 docBlockId 反查 itemID (行ID) */
function findItemIdByDoc(avID, docBlockId) {
  const data = get(avID);
  const blockKv = data.keyValues.find(kv => kv.key.type === 'block');
  if (!blockKv) throw new Error('数据库无 block 类型字段');
  for (const v of blockKv.values) {
    if ((v.block || {}).id === docBlockId) return v.blockID;
  }
  throw new Error(`找不到绑定文档 ${docBlockId} 的行`);
}

/** 获取数据库完整内容 */
function get(avID) {
  const out = run(`${SIYUAN} raw database get --av ${avID} -f json 2>/dev/null`);
  return JSON.parse(out);
}

/**
 * 更新单元格 —— 核心方法, 用临时文件传 value 避免引号问题
 * @param valueObj JS 对象, 如 {type:'text', text:{content:'...'}}
 */
function setCell(avID, keyID, itemID, valueObj) {
  const json = JSON.stringify(valueObj);
  fs.writeFileSync(TMP_VAL, json);
  const out = run(`${SIYUAN} raw database item update --av ${avID} --key ${keyID} --item ${itemID} --value "$(cat ${TMP_VAL})" 2>&1`);
  return out.trim() === 'ok';
}

// ===== 便捷方法 (自动构造正确嵌套结构) =====

function setCellText(avID, keyID, itemID, text) {
  return setCell(avID, keyID, itemID, { type: 'text', text: { content: String(text) } });
}

function setCellUrl(avID, keyID, itemID, url) {
  return setCell(avID, keyID, itemID, { type: 'url', url: { content: String(url) } });
}

function setCellSelect(avID, keyID, itemID, option) {
  // select 内部用 mSelect 数组! (思源 Value 结构体坑点)
  return setCell(avID, keyID, itemID, { type: 'select', mSelect: [{ content: String(option) }] });
}

function setCellMSelect(avID, keyID, itemID, options) {
  return setCell(avID, keyID, itemID, { type: 'mSelect', mSelect: options.map(o => ({ content: String(o) })) });
}

function setCellDate(avID, keyID, itemID, dateStr) {
  // dateStr: '2026-07-08' 或 Date 或 毫秒时间戳
  let ts;
  if (typeof dateStr === 'number') ts = dateStr;
  else if (dateStr instanceof Date) ts = dateStr.getTime();
  else ts = Date.parse(dateStr + 'T00:00:00Z');
  return setCell(avID, keyID, itemID, { type: 'date', date: { content: ts, isNotEmpty: true } });
}

function setCellCheckbox(avID, keyID, itemID, checked) {
  return setCell(avID, keyID, itemID, { type: 'checkbox', checkbox: { checked: !!checked } });
}

/**
 * 批量填一行记录的多个字段
 * @param fields {fieldName: value} - 值为 string 自动判类型, 或直接传 valueObj
 */
function fillRow(avID, itemID, fields) {
  const results = {};
  for (const [name, val] of Object.entries(fields)) {
    const kId = keyId(avID, name);
    let ok;
    if (val && typeof val === 'object' && val.type) {
      ok = setCell(avID, kId, itemID, val);
    } else if (typeof val === 'boolean') {
      ok = setCellCheckbox(avID, kId, itemID, val);
    } else {
      ok = setCellText(avID, kId, itemID, val);
    }
    results[name] = ok;
  }
  return results;
}

/** 删除行 */
function removeRows(avID, itemIds) {
  const ids = Array.isArray(itemIds) ? itemIds.join(',') : itemIds;
  return run(`${SIYUAN} raw database item remove --av ${avID} --ids ${ids} 2>&1`).trim() === 'ok';
}

/** 新增字段 */
function addKey(avID, name, type) {
  const out = run(`${SIYUAN} raw database key add --av ${avID} --name "${name}" --type ${type} -f json 2>&1`);
  try { return JSON.parse(out).id; } catch (e) { return null; }
}

/** 删除字段 */
function removeKey(avID, keyID) {
  return run(`${SIYUAN} raw database key remove --av ${avID} --key ${keyID} 2>&1`).trim() === 'ok';
}

/**
 * 验证数据库 —— 打印所有行所有字段实际值
 * 用法: node av_ops.js verify <avID>
 */
function verify(avID) {
  const data = get(avID);
  const blockKv = data.keyValues.find(kv => kv.key.type === 'block');
  if (!blockKv) { console.log('(无 block 字段)'); return; }

  for (const v of blockKv.values) {
    const iid = v.blockID;
    const title = (v.block || {}).content || '';
    console.log(`\n■ ${title} (${iid})`);
    for (const entry of data.keyValues) {
      if (entry.key.type === 'block') continue;
      const cell = (entry.values || []).find(c => c.blockID === iid);
      const val = cell ? formatVal(cell) : '(空)';
      console.log(`  ${entry.key.name.padEnd(10)} (${entry.key.type.padEnd(7)}) | ${val}`);
    }
  }
}

function formatVal(v) {
  const t = v.type;
  if (t === 'text') return (v.text || {}).content || '';
  if (t === 'url' || t === 'email' || t === 'phone') return (v[t] || {}).content || '';
  if (t === 'date') { const d = v.date || {}; return d.formattedContent || String(d.content || ''); }
  if (t === 'select' || t === 'mSelect') return (v.mSelect || []).map(c => c.content).join(',');
  if (t === 'checkbox') return (v.checkbox || {}).checked ? '✓' : '✗';
  if (t === 'template') return (v.template || {}).content || '';
  if (t === 'number') { const n = v.number || {}; return n.formattedContent || String(n.content || ''); }
  if (t === 'relation') return (v.relation || {}).blockIDs?.join(',') || '';
  if (t === 'mAsset') return (v.mAsset || []).map(a => a.name).join(',');
  return JSON.stringify(v).slice(0, 60);
}

/** 导出数据库为 JSON (备份) */
function exportJson(avID) {
  const data = get(avID);
  const rows = [];
  const blockKv = data.keyValues.find(kv => kv.key.type === 'block');
  for (const v of (blockKv || {}).values || []) {
    const row = { itemID: v.blockID, docID: (v.block || {}).id, title: (v.block || {}).content, fields: {} };
    rows.push(row);
  }
  for (const entry of data.keyValues) {
    if (entry.key.type === 'block') continue; // 跳过主键(block)字段
    const kname = entry.key.name;
    for (const v of entry.values || []) {
      const r = rows.find(r => r.itemID === v.blockID);
      if (r) r.fields[kname] = formatVal(v);
    }
  }
  return rows;
}

// ===== CLI 入口 =====
if (require.main === module) {
  const [, , cmd, ...args] = process.argv;
  try {
    if (cmd === 'search') {
      console.log(search(args[0]));
    } else if (cmd === 'keys') {
      console.log(listKeys(args[0]).map(k => `${k.id} | ${k.name} | ${k.type}`).join('\n'));
    } else if (cmd === 'verify') {
      verify(args[0]);
    } else if (cmd === 'export') {
      console.log(JSON.stringify(exportJson(args[0]), null, 2));
    } else if (cmd === 'get') {
      console.log(JSON.stringify(get(args[0]), null, 2));
    } else {
      console.log(`siyuan AV 工具库

用法:
  node av_ops.js search <库名>          按名查 avID
  node av_ops.js keys <avID>            列字段
  node av_ops.js verify <avID>         打印所有行字段实际值 (验证写入)
  node av_ops.js export <avID>          导出为 JSON
  node av_ops.js get <avID>             原始 get 输出

作为库 require:
  const av = require('./av_ops.js');
  const id = av.search('排查记录');
  av.verify(id);

便捷填值 (自动构造正确嵌套结构):
  av.setCellText(avID, keyID, itemID, '内容')
  av.setCellSelect(avID, keyID, itemID, '调课调讲')   // select 内部用 mSelect!
  av.setCellDate(avID, keyID, itemID, '2026-07-08')   // 自动转毫秒时间戳
  av.setCellCheckbox(avID, keyID, itemID, true)
  av.fillRow(avID, itemID, {业务模块:'调课调讲', 排查结论:'xxx'})`);
    }
  } catch (e) {
    console.error('Error:', e.message);
    process.exit(1);
  }
}

module.exports = {
  search, sql, listKeys, keyId, get,
  addRow, addDetachedRow, findItemIdByDoc,
  setCell, setCellText, setCellUrl, setCellSelect, setCellMSelect,
  setCellDate, setCellCheckbox, fillRow,
  removeRows, addKey, removeKey,
  verify, exportJson, formatVal,
};
