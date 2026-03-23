import std/[jsffi]
import karax/[kbase, jjson]
import ./[cache, config]
export config

const dbLoadingError* =
  "<div class=\"error\"><div class=\"err-icon\">⏳</div><p>Database belum selesai dimuat.</p></div>"

var sqlDb*: JsObject = nil
var dbLoadError*: kstring = ""
var dbLoading*: bool = false
var kategoriMap*: JsonNode = nil
var wordCache*: LRUCache

proc safeStr(
  node: JsonNode
): kstring {.importcpp: "(function(v){return v==null?'':String(v)})(#)".}

proc dbQuery*(sql: kstring): JsonNode =
  var arr: JsonNode
  {.emit: "`arr` = `sqlDb`.exec(`sql`);".}
  return arr

proc dbQuery*(sql: kstring, p1: kstring): JsonNode =
  var arr: JsonNode
  {.emit: "`arr` = `sqlDb`.exec(`sql`, [`p1`]);".}
  return arr

proc dbQuery*(sql: kstring, p1, p2: kstring): JsonNode =
  var arr: JsonNode
  {.emit: "`arr` = `sqlDb`.exec(`sql`, [`p1`,`p2`]);".}
  return arr

proc dbQuery*(sql: kstring, p1, p2, p3, p4, p5: kstring): JsonNode =
  var arr: JsonNode
  {.emit: "`arr` = `sqlDb`.exec(`sql`, [`p1`,`p2`,`p3`,`p4`,`p5`]);".}
  return arr

proc initKategoriMap*(): JsonNode =
  result = newJObject()

proc loadKategoriTable*(table: kstring, jenis: kstring, map: var JsonNode) =
  let rows = dbQuery("SELECT nilai, desc FROM " & table)
  if rows.isNil or rows.len == 0:
    return
  let vals = rows[0]["values"]
  if vals.isNil:
    return
  for i in 0 ..< vals.len:
    let row = vals[i]
    let key = jenis & ":" & safeStr(row[0])
    let desc = row[1]
    {.emit: "`map`[`key`] = `desc`;".}

proc initWordCache*() =
  wordCache = newLRUCache(maxWordCacheSize)

proc katGetSafe*(jenis, nilai: kstring, map: JsonNode): kstring =
  if map.isNil:
    return nilai
  var desc: kstring = ""
  let key = jenis & ":" & nilai
  {.
    emit: """
    `desc` = `map`[`key`];
    if (`desc` !== undefined) {
      `desc` = String(`desc`);
    } else {
      `desc` = '';
    }
  """
  .}
  return if desc == "": nilai else: desc

proc katGet*(jenis, nilai: kstring): kstring =
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

proc getResultRows*(res: JsonNode): seq[seq[kstring]] =
  if res.isNil or res.len == 0:
    return @[]
  let vals = res[0]["values"]
  if vals.isNil:
    return @[]
  for row in vals:
    var r: seq[kstring] = @[]
    var rowLen: int
    {.emit: "`rowLen` = (`row`||[]).length;".}
    for j in 0 ..< rowLen:
      r.add(safeStr(row[j]))
    result.add(r)

proc lookupWordById*(id: int): kstring =
  if sqlDb.isNil:
    return ""
  let idStr = kstring($id)
  let cached = lruGet(wordCache, idStr)
  if cached != "":
    return cached
  let rows = dbQuery("SELECT word FROM entries WHERE id=?", idStr)
  if rows.isNil or rows.len == 0:
    return ""
  let vals = rows[0]["values"]
  if vals.isNil or vals.len == 0:
    return ""
  let word = safeStr(vals[0][0])
  if word != "":
    lruSet(wordCache, idStr, word)
  return word

proc fetchEntrySyllable*(sensesJson: kstring): kstring =
  result = ""
  {.
    emit: """
    try {
      var _n = JSON.parse(`sensesJson`);
      var _arr = Array.isArray(_n) ? _n : (_n && _n.variants ? _n.variants[0].senses : []);
      for (var _i=0; _i<_arr.length; _i++) {
        if (_arr[_i].alt_form) { `result` = _arr[_i].alt_form; break; }
      }
    } catch(e) {}
  """
  .}
  return result

proc fetchEntrySenses*(entryId: kstring, word: kstring, kind: kstring): kstring =
  result = "[]"
  {.
    emit: """
  try {
    var entryId = `entryId`;
    var isGroup = (`kind` === 'group');

    var sRows = `sqlDb`.exec(
      'SELECT id,entry_word,entry_kind,' +
      'number,pos,bahasa,bidang,ragam,markers,text,' +
      'altForm,altText,latin,abbrev,link,chem ' +
      'FROM senses WHERE entry_id=? ORDER BY id', [entryId]);
    if (!sRows.length || !sRows[0].values.length) { `result` = '[]'; return; }

    var senseRows = sRows[0].values;
    var senseIds = senseRows.map(function(r){ return r[0]; });

    var exMap = {};
    if (senseIds.length > 0) {
      var exRows = `sqlDb`.exec(
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
      var xrRows = `sqlDb`.exec(
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
      var xgRows = `sqlDb`.exec(
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
      `result` = JSON.stringify(senseRows.map(buildSenseObj));
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
      `result` = JSON.stringify({
        group: true,
        variants: variantOrder.map(function(k){ return variantMap[k]; })
      });
    }
  } catch(e) { console.warn('fetchEntrySenses failed', e); }
  """
  .}
  return result
