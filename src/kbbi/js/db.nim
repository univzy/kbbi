import std/jsffi
import ./[cache, config, ffi]

const dbLoadingError* =
  "<div class=\"error\"><div class=\"err-icon\">⏳</div><p>Database belum selesai dimuat.</p></div>"

var sqlDb*: JsObject = nil
var dbLoadError*: cstring = ""
var dbLoading*: bool = false
var kategoriMap*: JsObject = nil
var wordCache*: LRUCache

proc initKategoriMap*(): JsObject =
  var m: JsObject
  {.emit: [m, " = {};"].}
  return m

proc loadKategoriTable*(table: cstring, jenis: cstring, map: var JsObject) =
  {.
    emit: [
      """
    try {
      var rows = """, sqlDb,
      """.exec('SELECT nilai, desc FROM ' + """, table,
      """);
      if (rows && rows.length > 0) {
        rows[0].values.forEach(function(r){
          """,
      map, """[""", jenis,
      """ + ':' + r[0]] = r[1];
        });
      }
    } catch(e) { console.warn('kategori load failed for ' + """,
      table,
      """, e); }
  """,
    ]
  .}

proc initWordCache*() =
  wordCache = newLRUCache(maxWordCacheSize)

proc katGetSafe*(jenis, nilai: cstring, map: JsObject): cstring =
  if map.isNil:
    return nilai
  var desc: cstring = ""
  let key = jenis & ":" & nilai
  {.
    emit: [
      desc, " = ", map, "[", key, "];", "if (", desc, " !== undefined) { ", desc,
      " = String(", desc, "); } else { ", desc, " = ''; }",
    ]
  .}
  return if desc == "": nilai else: desc

proc katGet*(jenis, nilai: cstring): cstring =
  katGetSafe(jenis, nilai, kategoriMap)

proc loadKategori*() =
  if sqlDb.isNil:
    return
  kategoriMap = initKategoriMap()
  loadKategoriTable("kategori_bahasa", "bahasa", kategoriMap)
  loadKategoriTable("kategori_bidang", "bidang", kategoriMap)
  loadKategoriTable("kategori_ragam", "ragam", kategoriMap)
  loadKategoriTable("kategori_kelas", "kelas", kategoriMap)
  loadKategoriTable("kategori_jenis", "jenis", kategoriMap)

proc dbQuery*(sql: cstring, p1: cstring): JsObject =
  var arr: JsObject
  {.emit: [arr, " = ", sqlDb, ".exec(", sql, ", [", p1, "]);"].}
  return arr

proc dbQuery2*(sql: cstring, p1, p2: cstring): JsObject =
  var arr: JsObject
  {.emit: [arr, " = ", sqlDb, ".exec(", sql, ", [", p1, ",", p2, "]);"].}
  return arr

proc getResultRows*(res: JsObject): seq[seq[cstring]] =
  if res.isNil or jsLength(res) == 0:
    return @[]
  let block0 = jsItem(res, 0)
  let vals = jsGet(block0, "values")
  if vals.isNil:
    return @[]
  let numRows = jsLength(vals)
  for i in 0 ..< numRows:
    let row = jsItem(vals, i)
    var r: seq[cstring] = @[]
    var rowLen: int
    {.emit: [rowLen, " = (", row, "||[]).length;"].}
    for j in 0 ..< rowLen:
      var cell: JsObject
      {.emit: [cell, " = ", row, "[", j, "];"].}
      r.add(jsStr(cell))
    result.add(r)

proc lookupWordById*(id: int): cstring =
  if sqlDb.isNil:
    return ""
  let idStr = cstring($id)
  let cached = lruGet(wordCache, idStr)
  if cached != "":
    return cached
  var word: cstring = ""
  {.
    emit: [
      """try {
    var _r=""", sqlDb,
      """.exec("SELECT word FROM entries WHERE id=?",[""", idStr,
      """]);
    if(_r.length>0&&_r[0].values.length>0) """, word,
      """=String(_r[0].values[0][0]||'');
  } catch(e) {}""",
    ]
  .}
  if word != "":
    lruSet(wordCache, idStr, word)
  return word

proc fetchEntrySyllable*(sensesJson: cstring): cstring =
  result = ""
  {.
    emit: [
      """try {
    var _n = JSON.parse(""", sensesJson,
      """);
    var _arr = Array.isArray(_n) ? _n : (_n && _n.variants ? _n.variants[0].senses : []);
    for (var _i=0; _i<_arr.length; _i++) {
      if (_arr[_i].alt_form) { """,
      result,
      """ = _arr[_i].alt_form; break; }
    }
  } catch(e) {}""",
    ]
  .}
  return result

proc fetchEntrySenses*(entryId: cstring, word: cstring, kind: cstring): cstring =
  result = "[]"
  {.
    emit: [
      """
  try {
    var entryId = """, entryId,
      """;
    var isGroup = (""", kind,
      """ === 'group');

    var sRows = """, sqlDb,
      """.exec(
      'SELECT id,entry_word,entry_kind,' +
      'number,pos,bahasa,bidang,ragam,markers,text,' +
      'altForm,altText,latin,abbrev,link,chem ' +
      'FROM senses WHERE entry_id=? ORDER BY id', [entryId]);
    if (!sRows.length || !sRows[0].values.length) { """,
      result,
      """ = '[]'; return; }

    var senseRows = sRows[0].values;
    var senseIds = senseRows.map(function(r){ return r[0]; });

    var exMap = {};
    if (senseIds.length > 0) {
      var exRows = """,
      sqlDb,
      """.exec(
        'SELECT sense_id, example FROM sense_examples WHERE sense_id IN (' +
        senseIds.join(',') + ') ORDER BY id');
      if (exRows.length && exRows[0].values.length) {
        exRows[0].values.forEach(function(r){
          if (!exMap[r[0]]) exMap[r[0]] = [];
          exMap[r[0]].push(r[1]);
        });
      }
    }

    var xrMap = {};
    if (senseIds.length > 0) {
      var xrRows = """,
      sqlDb,
      """.exec(
        'SELECT sense_id, xref_id FROM sense_xrefs WHERE sense_id IN (' +
        senseIds.join(',') + ')');
      if (xrRows.length && xrRows[0].values.length) {
        xrRows[0].values.forEach(function(r){
          if (!xrMap[r[0]]) xrMap[r[0]] = [];
          xrMap[r[0]].push(r[1]);
        });
      }
    }

    var xgMap = {};
    if (senseIds.length > 0) {
      var xgRows = """,
      sqlDb,
      """.exec(
        'SELECT sense_id, kind, ref_id FROM sense_xref_groups WHERE sense_id IN (' +
        senseIds.join(',') + ') ORDER BY id');
      if (xgRows.length && xgRows[0].values.length) {
        xgRows[0].values.forEach(function(r){
          var sid = r[0], k = r[1], ref = r[2];
          if (!xgMap[sid]) xgMap[sid] = {};
          if (!xgMap[sid][k]) xgMap[sid][k] = [];
          xgMap[sid][k].push(ref);
        });
      }
    }

    function buildSenseObj(r) {
      var sid = r[0];
      var s = {};
      if (r[3])  s['number']   = r[3];
      if (r[4])  s['pos']      = r[4];
      if (r[5])  s['bahasa']   = r[5];
      if (r[6])  s['bidang']   = r[6];
      if (r[7])  s['ragam']    = r[7];
      if (r[8])  s['markers']  = r[8];
      if (r[9])  s['text']     = r[9];
      if (r[10]) s['alt_form'] = r[10];
      if (r[11]) s['alt_text'] = r[11];
      if (r[12]) s['latin']    = r[12];
      if (r[13]) s['abbrev']   = r[13];
      if (r[14]) s['link']     = r[14];
      if (r[15]) s['chem']     = r[15];
      if (exMap[sid]) s['examples']   = exMap[sid];
      if (xrMap[sid]) s['xrefs']      = xrMap[sid];
      if (xgMap[sid]) s['xref_groups'] = Object.keys(xgMap[sid]).map(function(k){
        return {kind: k, refs: xgMap[sid][k]};
      });
      return s;
    }

    if (!isGroup) {
      """,
      result,
      """ = JSON.stringify(senseRows.map(buildSenseObj));
    } else {
      var variantOrder = [];
      var variantMap = {};
      senseRows.forEach(function(r) {
        var vw = r[1] || '', vk = r[2] || '';
        var key = vw + '\x00' + vk;
        if (!variantMap[key]) {
          variantMap[key] = {word: vw, kind: vk, senses: []};
          variantOrder.push(key);
        }
        variantMap[key].senses.push(buildSenseObj(r));
      });
      """,
      result,
      """ = JSON.stringify({
        group: true,
        variants: variantOrder.map(function(k){ return variantMap[k]; })
      });
    }
  } catch(e) { console.warn('fetchEntrySenses failed', e); }
  """,
    ]
  .}
  return result
