import std/[dom, jsffi, asyncjs, strutils]
import kbbi/[config]

proc arrayBuffer(resp: JsObject): Future[JsObject] {.importjs: "#.arrayBuffer()".}
proc uint8Array(buf: JsObject): JsObject {.importjs: "new Uint8Array(#)".}
proc initSqlJs(cfg: JsObject): Future[JsObject] {.importjs: "initSqlJs(#)".}
proc newDb(SQL: JsObject, data: JsObject): JsObject {.importjs: "new #.Database(#)".}
proc jsGet(obj: JsObject, key: cstring): JsObject {.importjs: "#[#]".}
proc jsLength(arr: JsObject): int {.importjs: "(#||[]).length".}
proc jsItem(arr: JsObject, idx: int): JsObject {.importjs: "#[#]".}
proc jsStr(obj: JsObject): cstring {.importjs: "String(#||'')".}
proc jsInt(obj: JsObject): int {.importjs: "(Number(#)||0)".}
proc setInnerHTML(el: Element, html: cstring) {.importjs: "#.innerHTML = #".}
proc getValue(el: Element): cstring {.importjs: "#.value".}
proc setValue(el: Element, v: cstring) {.importjs: "#.value = #".}
proc getById(id: cstring): Element {.importjs: "document.getElementById(#)".}
proc focusEl(el: Element) {.importjs: "#.focus()".}
proc smoothScroll(el: Element) {.importjs: "#.scrollIntoView({behavior:'smooth',block:'start'})".}
proc addKbListener(el: Element, fn: proc(ev: KeyboardEvent)) {.importjs: "#.addEventListener('keydown',#)".}
proc addClickListener(el: Element, fn: proc(ev: Event)) {.importjs: "#.addEventListener('click',#)".}
proc addChangeListener(el: Element, fn: proc(ev: Event)) {.importjs: "#.addEventListener('change',#)".}
proc querySelectorAll(el: Element, sel: cstring): JsObject {.importjs: "#.querySelectorAll(#)".}
proc contains(el: Element, other: Element): bool {.importjs: "#.contains(#)".}
proc getAttribute(el: Element, name: cstring): cstring {.importjs: "#.getAttribute(#)".}
proc setAttribute(el: Element, name, value: cstring) {.importjs: "#.setAttribute(#,#)".}
proc scrollIntoViewNearest(el: Element) {.importjs: "#.scrollIntoView({block:'nearest'})".}
proc dispatchChange(el: Element) {.importjs: "#.dispatchEvent(new Event('change',{bubbles:true}))".}
proc elTextContent(el: Element, s: cstring) {.importjs: "#.textContent = #".}
proc dataValue(el: Element): cstring {.importjs: "#.dataset.value".}
proc closestOpt(el: Element): Element {.importjs: "#.closest('.cp-select__option[data-value]')".}
proc setGlobalCpSelect(fn: proc(v: cstring)) {.importjs: "window.cpSelectSetValue = #".}

proc localStorageSetItem(key, value: cstring) {.importjs: "localStorage.setItem(#, #)".}
proc localStorageGetItem(key: cstring): cstring {.importjs: "localStorage.getItem(#) || ''".}

proc normalizeWord(s: cstring): cstring {.importjs: "(#).toLowerCase()".}

proc removeNumberTag(s: cstring): cstring {.importjs: """
  (#.replace(/\s*\(\d+\)/g, "").trim())
""".}

proc fuzzyNormWord(s: cstring): cstring {.importjs: """(function(s){
  return s.toLowerCase().replace(/[^a-z0-9\u0080-\uffff]/g,'');
})(#)""".}

proc replaceHeadword(example, headword: cstring): cstring {.importjs: """
  (function(ex, hw){ return ex.replace(/--|~/g, hw); })(#, #)
""".}

proc htmlEsc(s: cstring): cstring {.importjs: """
  (function(s){ return String(s||'')
    .replace(/&/g,'&amp;')
    .replace(/</g,'&lt;')
    .replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;'); })(#)
""".}

proc nextChar(s: cstring): cstring {.importjs: """
  (function(s){ return s.length>0 ? s.slice(0,-1)+String.fromCharCode(s.charCodeAt(s.length-1)+1) : '\xff'; })(#)
""".}

proc jsStrEsc(s: cstring): cstring {.importjs: """
  (function(s){ return String(s||'').replace(/\\/g,'\\\\').replace(/"/g,'\\"'); })(#)
""".}

proc isValidString(s: cstring): bool {.inline.} =
  s != "" and s != "null" and s != "undefined"

proc buildDataButton(text, action, attrValue: cstring, ariaLabel: cstring = ""): cstring =
  let htmlText = htmlEsc(text)
  let aria: cstring = if ariaLabel != "": " aria-label=\"" & htmlEsc(ariaLabel) & "\"" else: ""
  case $action
  of "search":
    let htmlAttr = htmlEsc(attrValue)
    return "<button class=\"inline-link\" data-action=\"search\" data-query=\"" & htmlAttr & "\"" & aria & ">" & htmlText & "</button>"
  of "search-id":
    return "<button class=\"xref-link\" data-action=\"search-id\" data-id=\"" & attrValue & "\"" & aria & ">" & htmlText & "</button>"
  else:
    return "<button>" & htmlText & "</button>"

const DB_LOADING_ERROR = "<div class=\"error\"><div class=\"err-icon\">⏳</div><p>Database belum selesai dimuat.</p></div>"

type
  LRUCache = object
    entries: seq[(cstring, cstring)]
    maxSize: int

proc newLRUCache(maxSize: int): LRUCache =
  LRUCache(entries: @[], maxSize: maxSize)

proc lruGet(cache: var LRUCache, key: cstring): cstring =
  for i in 0 ..< cache.entries.len:
    if cache.entries[i][0] == key:
      let val = cache.entries[i][1]
      cache.entries.delete(i)
      cache.entries.insert((key, val), 0)
      return val
  return ""

proc lruSet(cache: var LRUCache, key: cstring, value: cstring) =
  for i in 0 ..< cache.entries.len:
    if cache.entries[i][0] == key:
      cache.entries.delete(i)
      cache.entries.insert((key, value), 0)
      return
  if cache.entries.len >= cache.maxSize:
    cache.entries.setLen(cache.maxSize - 1)
  cache.entries.insert((key, value), 0)

var db: JsObject = nil
var searchHistory: seq[cstring] = @[]
var dbLoadError: cstring = ""
var kategoriMap: JsObject = nil
var wordCache: LRUCache

proc initWordCache() =
  wordCache = newLRUCache(MAX_WORD_CACHE_SIZE)

proc katGet(jenis, nilai: cstring): cstring =
  if kategoriMap.isNil: return nilai
  var desc: cstring = ""
  let key = jenis & ":" & nilai
  {.emit: [desc, " = ", kategoriMap, "[", key, "] || '';"].}
  return if desc == "": nilai else: desc

proc loadKategori() =
  if db.isNil: return
  {.emit: ["""
    try {
      """, kategoriMap, """ = {};
      var tables = [
        ['bahasa', 'kategori_bahasa'],
        ['bidang', 'kategori_bidang'],
        ['ragam',  'kategori_ragam'],
        ['kelas',  'kategori_kelas'],
        ['jenis',  'kategori_jenis']
      ];
      tables.forEach(function(t) {
        try {
          var rows = """, db, """.exec('SELECT nilai, desc FROM ' + t[1]);
          if (rows.length > 0) {
            rows[0].values.forEach(function(r){
              """, kategoriMap, """[t[0] + ':' + r[0]] = r[1];
            });
          }
        } catch(e) { console.warn('kategori load failed for ' + t[1], e); }
      });
    } catch(e) { console.warn('loadKategori failed', e); }
  """].}

proc setText(id: cstring, html: cstring) =
  let el = getById(id)
  if not el.isNil: setInnerHTML(el, html)

proc setClass(id: cstring, cls: cstring, add: bool) =
  let el = getById(id)
  if el.isNil: return
  if add: el.classList.add(cls) else: el.classList.remove(cls)

proc setLoading(on: bool) =
  setClass("search-btn", "loading", on)
  setClass("spinner", "hidden", not on)
  let lbl: cstring = if on: "Mencari..." else: "Cari"
  setText("btn-text", lbl)

proc saveHistoryToStorage() =
  if searchHistory.len == 0:
    localStorageSetItem(KEY_SEARCH_HISTORY, "")
    return
  var jsonStr: cstring = "["
  for i in 0 ..< searchHistory.len:
    let h = searchHistory[i]
    jsonStr = jsonStr & "\"" & jsStrEsc(h) & "\""
    if i < searchHistory.len - 1: jsonStr = jsonStr & ","
  jsonStr = jsonStr & "]"
  localStorageSetItem(KEY_SEARCH_HISTORY, jsonStr)

proc loadHistoryFromStorage*() {.exportc.} =
  let stored = localStorageGetItem(KEY_SEARCH_HISTORY)
  searchHistory = @[]
  if stored == "": return
  var items: JsObject
  {.emit: ["try { ", items, " = JSON.parse(", stored, "); } catch(e) { ", items, " = []; }"].}
  if not items.isNil:
    let len = jsLength(items)
    for i in 0 ..< len:
      let item = jsStr(jsItem(items, i))
      if item != "": searchHistory.add(item)

proc renderHistory() =
  var html: cstring = ""
  for h in searchHistory:
    html = html & "<button class=\"hist-item\" data-action=\"search\" data-query=\"" & htmlEsc(h) & "\" role=\"listitem\">" & htmlEsc(h) & "</button>"
  setText("history-list", html)
  setClass("history-section", "hidden", searchHistory.len == 0)

proc updateHistory(word: cstring) =
  let normWord = normalizeWord(word)
  var filtered: seq[cstring] = @[]
  for h in searchHistory:
    if normalizeWord(h) != normWord: filtered.add(h)
  searchHistory = filtered
  searchHistory.insert(word, 0)
  if searchHistory.len > MAX_HISTORY: searchHistory = searchHistory[0..MAX_HISTORY-1]
  saveHistoryToStorage()
  renderHistory()

proc clearHistory*() {.exportc.} =
  searchHistory = @[]
  saveHistoryToStorage()
  renderHistory()

proc badgeWithTooltip(cls, code, jenis: cstring): cstring =
  let desc = katGet(jenis, code)
  let title: cstring = if desc != code: " title=\"" & htmlEsc(desc) & "\"" else: ""
  return "<span class=\"badge " & cls & "\"" & title & ">" & htmlEsc(code) & "</span>"

proc kindBadgeHtml(kind: cstring): cstring =
  case $kind
  of "foreign":     return "<span class=\"kind-badge foreign\" title=\"Kata/ungkapan asing\">asing</span>"
  of "phrase":      return "<span class=\"kind-badge phrase\" title=\"Frasa\">frasa</span>"
  of "nonstandard": return "<span class=\"kind-badge nonstandard\" title=\"Ejaan tidak baku\">tidak baku</span>"
  of "alias":       return "<span class=\"kind-badge alias\" title=\"Alias\">alias</span>"
  of "redirect":    return "<span class=\"kind-badge redirect\" title=\"Merujuk ke entri lain\">lihat</span>"
  of "group":       return "<span class=\"kind-badge group\" title=\"Beberapa entri berbagi satu kunci\">grup</span>"
  else:             return ""

proc markerBadge(m: cstring): cstring =
  case $m
  of "ki":   return "<span class=\"badge marker\" title=\"Kiasan (figuratif/idiom)\">ki</span>"
  of "sing": return "<span class=\"badge marker\" title=\"Singkatan\">sing</span>"
  of "akr":  return "<span class=\"badge marker\" title=\"Akronim\">akr</span>"
  of "ukp":  return "<span class=\"badge marker\" title=\"Ungkapan (ekspresi asing)\">ukp</span>"
  else:      return "<span class=\"badge marker\">" & htmlEsc(m) & "</span>"

proc renderMarkerBadges(m: cstring): cstring =
  if not isValidString(m): return ""
  var badges: cstring = ""
  let ms = ($m).split(",")
  for mk in ms:
    let mkc = mk.strip()
    if mkc != "": badges = badges & markerBadge(cstring(mkc))
  return badges

proc xrefGroupLabel(kind: cstring): cstring =
  case $kind
  of "baku":       return "<span class=\"xref-kind baku\" title=\"Bentuk baku\">bentuk baku</span>"
  of "dasar":      return "<span class=\"xref-kind dasar\" title=\"Kata dasar\">kata dasar</span>"
  of "lihat":      return "<span class=\"xref-kind lihat\" title=\"Lihat juga\">lihat juga</span>"
  of "turunan":    return "<span class=\"xref-kind turunan\" title=\"Kata turunan\">kata turunan</span>"
  of "gabungan":   return "<span class=\"xref-kind gabungan\" title=\"Kata gabungan\">kata gabungan</span>"
  of "peribahasa": return "<span class=\"xref-kind peribahasa\" title=\"Peribahasa\">peribahasa</span>"
  else:            return "<span class=\"xref-kind tidak-baku\" title=\"Bentuk tidak baku\">bentuk tidak baku</span>"

proc dbQuery(sql: cstring, p1: cstring): JsObject =
  var arr: JsObject
  {.emit: [arr, " = ", db, ".exec(", sql, ", [", p1, "]);"].}
  return arr

proc dbQuery2(sql: cstring, p1, p2: cstring): JsObject =
  var arr: JsObject
  {.emit: [arr, " = ", db, ".exec(", sql, ", [", p1, ",", p2, "]);"].}
  return arr

proc getResultRows(res: JsObject): seq[seq[cstring]] =
  if res.isNil or jsLength(res) == 0: return @[]
  let block0 = jsItem(res, 0)
  let vals   = jsGet(block0, "values")
  if vals.isNil: return @[]
  let numRows = jsLength(vals)
  for i in 0..<numRows:
    let row = jsItem(vals, i)
    var r: seq[cstring] = @[]
    var rowLen: int
    {.emit: [rowLen, " = (", row, "||[]).length;"].}
    for j in 0..<rowLen:
      var cell: JsObject
      {.emit: [cell, " = ", row, "[", j, "];"].}
      r.add(jsStr(cell))
    result.add(r)

proc lookupWordById(id: int): cstring =
  if db.isNil: return ""
  let idStr = cstring($id)
  let cached = lruGet(wordCache, idStr)
  if cached != "": return cached
  var word: cstring = ""
  {.emit: ["""try {
    var _r=""", db, """.exec("SELECT word FROM entries WHERE id=?",[""", idStr, """]);
    if(_r.length>0&&_r[0].values.length>0) """, word, """=String(_r[0].values[0][0]||'');
  } catch(e) {}"""].}
  if word != "":
    lruSet(wordCache, idStr, word)
  return word

proc fetchEntrySyllable(sensesJson: cstring): cstring =
  result = ""
  {.emit: ["""try {
    var _n = JSON.parse(""", sensesJson, """);
    var _arr = Array.isArray(_n) ? _n : (_n && _n.variants ? _n.variants[0].senses : []);
    for (var _i=0; _i<_arr.length; _i++) {
      if (_arr[_i].alt_form) { """, result, """ = _arr[_i].alt_form; break; }
    }
  } catch(e) {}"""].}
  return result

proc fetchEntrySenses(entryId: cstring, word: cstring, kind: cstring): cstring =
  result = "[]"
  {.emit: ["""
  try {
    var entryId = """, entryId, """;
    var isGroup = (""", kind, """ === 'group');

    var sRows = """, db, """.exec(
      'SELECT id,entry_word,entry_kind,' +
      'number,pos,bahasa,bidang,ragam,markers,text,' +
      'altForm,altText,latin,abbrev,link,chem ' +
      'FROM senses WHERE entry_id=? ORDER BY id', [entryId]);
    if (!sRows.length || !sRows[0].values.length) { """, result, """ = '[]'; return; }

    var senseRows = sRows[0].values;
    var senseIds = senseRows.map(function(r){ return r[0]; });

    var exMap = {};
    if (senseIds.length > 0) {
      var exRows = """, db, """.exec(
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
      var xrRows = """, db, """.exec(
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
      var xgRows = """, db, """.exec(
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
      """, result, """ = JSON.stringify(senseRows.map(buildSenseObj));
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
      """, result, """ = JSON.stringify({
        group: true,
        variants: variantOrder.map(function(k){ return variantMap[k]; })
      });
    }
  } catch(e) { console.warn('fetchEntrySenses failed', e); }
  """].}
  return result

proc buildXrefLinks(xrArr: JsObject): seq[cstring] =
  var links: seq[cstring] = @[]
  if xrArr.isNil or jsLength(xrArr) == 0: return links
  for i in 0..<jsLength(xrArr):
    let id = jsInt(jsItem(xrArr, i))
    if id == 0: continue
    let w = lookupWordById(id)
    if isValidString(w):
      links.add(buildDataButton(w, "search-id", cstring($id), w))
    else:
      links.add("<span class=\"xref-id\">#" & cstring($id) & "</span>")
  return links

proc renderXrefs(xrArr: JsObject): cstring =
  let links = buildXrefLinks(xrArr)
  if links.len == 0: return ""
  var html: cstring = "<div class=\"xrefs plain\">"
  for lk in links: html = html & lk
  return html & "</div>"

proc renderXrefsWithLabel(xrArr: JsObject, label: cstring): cstring =
  let links = buildXrefLinks(xrArr)
  if links.len == 0: return ""
  var html: cstring = "<div class=\"xref-group\">" & xrefGroupLabel(label)
  for lk in links: html = html & lk
  return html & "</div>"

proc renderXrefGroups(xgArr: JsObject): cstring =
  if xgArr.isNil or jsLength(xgArr) == 0: return ""
  var html: cstring = ""
  for i in 0..<jsLength(xgArr):
    let grp  = jsItem(xgArr, i)
    let kind = jsStr(jsGet(grp, "kind"))
    let refs = jsGet(grp, "refs")
    let links = buildXrefLinks(refs)
    if links.len == 0: continue
    html = html & "<div class=\"xref-group\">" & xrefGroupLabel(kind)
    for lk in links: html = html & lk
    html = html & "</div>"
  return html

proc renderSense(s: JsObject, headword: cstring,
                 suppressXrefGroups = false,
                 xrefsLabel: cstring = ""): cstring =
  let num = jsStr(jsGet(s, "number"))
  let p   = jsStr(jsGet(s, "pos"))
  let bh  = jsStr(jsGet(s, "bahasa"))
  let bd  = jsStr(jsGet(s, "bidang"))
  let r   = jsStr(jsGet(s, "ragam"))
  let m   = jsStr(jsGet(s, "markers"))
  let t   = jsStr(jsGet(s, "text"))
  let at  = jsStr(jsGet(s, "alt_text"))
  let l   = jsStr(jsGet(s, "latin"))
  let ab  = jsStr(jsGet(s, "abbrev"))
  let lk  = jsStr(jsGet(s, "link"))
  let ch  = jsStr(jsGet(s, "chem"))

  var numHtml: cstring = ""
  if isValidString(num):
    numHtml = "<span class=\"sense-num\">" & htmlEsc(num) & "</span>"

  var badges: cstring = ""
  if isValidString(p):  badges = badges & badgeWithTooltip("kelas",  p,  "kelas")
  if isValidString(bh): badges = badges & badgeWithTooltip("bahasa", bh, "bahasa")
  if isValidString(bd):
    let bdDesc = katGet("bidang", bd)
    let bdTitle: cstring = if bdDesc != bd: " title=\"" & htmlEsc(bdDesc) & "\"" else: ""
    badges = badges & "<span class=\"badge bidang\"" & bdTitle & ">[" & htmlEsc(bd) & "]</span>"
  if isValidString(r):  badges = badges & badgeWithTooltip("ragam",  r,  "ragam")
  badges = badges & renderMarkerBadges(m)

  var body: cstring = ""
  if isValidString(t):  
    let esc_t = htmlEsc(t)
    body = body & "<span class=\"def-text\">" & esc_t & "</span>"
  if isValidString(ab): 
    let esc_ab = htmlEsc(ab)
    body = body & " <span class=\"def-abbrev\" title=\"Kepanjangan singkatan\">(" & esc_ab & ")</span>"
  if isValidString(at):
    body = body & " <span class=\"def-note\">lihat: " & buildDataButton(at, "search", at, at) & "</span>"
  if isValidString(lk):
    body = body & " <span class=\"def-note\">= " & buildDataButton(lk, "search", lk, lk) & "</span>"
  if isValidString(l):  
    let esc_l = htmlEsc(l)
    body = body & " <span class=\"def-latin\"><em>" & esc_l & "</em></span>"
  if isValidString(ch): 
    let esc_ch = htmlEsc(ch)
    body = body & " <span class=\"def-chem\">" & esc_ch & "</span>"

  var exHtml: cstring = ""
  let exArr = jsGet(s, "examples")
  if not exArr.isNil and jsLength(exArr) > 0:
    exHtml = "<ul class=\"examples\" role=\"list\">"
    for i in 0..<jsLength(exArr):
      let raw = jsStr(jsItem(exArr, i))
      let ex  = replaceHeadword(raw, headword)
      exHtml = exHtml & "<li role=\"listitem\">" & htmlEsc(ex) & "</li>"
    exHtml = exHtml & "</ul>"

  let xrefs = jsGet(s, "xrefs")
  let xrHtml = if xrefsLabel != "":
    renderXrefsWithLabel(xrefs, xrefsLabel)
  else:
    renderXrefs(xrefs)
  let xgHtml: cstring = if suppressXrefGroups: "" else: renderXrefGroups(jsGet(s, "xref_groups"))

  return "<li class=\"sense-item\">" &
    numHtml &
    "<div class=\"sense-right\">" &
      "<div class=\"sense-meta\">" & badges & "</div>" &
      "<div class=\"sense-body\">" & body & exHtml & xrHtml & xgHtml & "</div>" &
    "</div>" &
    "</li>"

proc renderRedirectCard(word, kind, entryId: cstring): cstring =
  var targets: cstring = ""
  let atRows = getResultRows(dbQuery("""
    SELECT altText FROM senses WHERE entry_id=? AND altText != '' LIMIT 1""", entryId))
  if atRows.len > 0 and atRows[0].len > 0 and isValidString(atRows[0][0]):
    let at = atRows[0][0]
    targets = "<button class=\"xref-link prominent\" data-action=\"search\" data-query=\"" & htmlEsc(at) & "\" aria-label=\"Cari: " & htmlEsc(at) & "\">" & htmlEsc(at) & " →</button>"
  else:
    let xrRows = getResultRows(dbQuery("""
      SELECT sx.xref_id FROM senses s
      JOIN sense_xrefs sx ON sx.sense_id = s.id
      WHERE s.entry_id=? LIMIT 5""", entryId))
    if xrRows.len > 0:
      var links: cstring = ""
      for row in xrRows:
        if row.len == 0: continue
        let id = row[0]
        let w = lookupWordById(($id).parseInt)
        if isValidString(w):
          links = links & buildDataButton(w, "search-id", id, w)
      if links != "": targets = links
    if targets == "":
      let xgRows = getResultRows(dbQuery("""
        SELECT sxg.ref_id FROM senses s
        JOIN sense_xref_groups sxg ON sxg.sense_id = s.id
        WHERE s.entry_id=? AND sxg.kind='baku' LIMIT 5""", entryId))
      if xgRows.len > 0:
        var links: cstring = ""
        for row in xgRows:
          if row.len == 0: continue
          let id = row[0]
          let w = lookupWordById(($id).parseInt)
          if isValidString(w):
            links = links & buildDataButton(w, "search-id", id, w)
        if links != "": targets = links
    if targets == "":
      let revRows = getResultRows(dbQuery("""
        SELECT DISTINCT e.id, e.word FROM sense_xref_groups sxg
        JOIN senses s ON s.id = sxg.sense_id
        JOIN entries e ON e.id = s.entry_id
        WHERE sxg.ref_id=? AND sxg.kind='baku' LIMIT 5""", entryId))
      if revRows.len > 0:
        var links: cstring = ""
        for row in revRows:
          if row.len < 2: continue
          let id = row[0]
          let w  = row[1]
          if isValidString(w):
            links = links & buildDataButton(w, "search-id", id, w)
        if links != "": targets = links

  let lbl: cstring = case $kind
    of "alias":    "merupakan alias dari"
    of "redirect": "merujuk ke"
    else:          "varian dari"
  return "<div class=\"redirect-card\">" &
    "<span class=\"redirect-icon\">↪</span>" &
    "<div class=\"redirect-body\">" &
      "<span class=\"redirect-word\">" & htmlEsc(word) & "</span>" &
      "<span class=\"redirect-label\"> " & lbl & " </span>" &
      targets &
    "</div></div>"

proc renderEntry(word, kind, entryId, sensesJson: cstring): cstring =
  let kindStr = $kind
  if kindStr == "redirect" or kindStr == "alias":
    return renderRedirectCard(word, kind, entryId)

  if sensesJson == "" or sensesJson == "[]": return ""

  var node: JsObject
  {.emit: ["""try { """, node, """ = JSON.parse(""", sensesJson, """); } catch(e) {}"""].}
  if node.isNil or jsLength(node) == 0: return ""

  var html: cstring = ""
  var isGroup: bool
  {.emit: [isGroup, " = !!(", node, " && ", node, "['group']);"].}

  if isGroup:
    let variants = jsGet(node, "variants")
    if variants.isNil: return ""
    let variantCount = jsLength(variants)
    for i in 0..<variantCount:
      let v  = jsItem(variants, i)
      let vw = jsStr(jsGet(v, "word"))
      let vk = jsStr(jsGet(v, "kind"))
      let ss = jsGet(v, "senses")
      let displayWord: cstring = if vw != "" and vw != "null": vw else: word
      let showBadge = not (variantCount == 1 and $vk == "nonstandard")
      html = html & "<div class=\"variant\">" &
        "<div class=\"variant-head\"><em>" & htmlEsc(displayWord) & "</em>" &
        (if showBadge: kindBadgeHtml(vk) else: "") & "</div>" &
        "<ol class=\"sense-list\">"
      if not ss.isNil:
        for j in 0..<jsLength(ss):
          let isNonstandard = $vk == "nonstandard"
          html = html & renderSense(jsItem(ss, j), displayWord,
            suppressXrefGroups = false,
            xrefsLabel = if isNonstandard: cstring("tidak-baku") else: "")
      html = html & "</ol></div>"
  else:
    html = "<ol class=\"sense-list\">"
    for i in 0..<jsLength(node):
      html = html & renderSense(jsItem(node, i), word)
    html = html & "</ol>"

  return html

proc buildResultCards(rows: seq[seq[cstring]]): cstring =
  var html: cstring = ""
  for row in rows:
    if row.len < 4: continue
    let id   = row[0]
    let word = row[2]
    let kind = row[3]

    let sensesJson = fetchEntrySenses(id, word, kind)
    let syllable = fetchEntrySyllable(sensesJson)
    let syllableHtml: cstring =
      if isValidString(syllable): " <span class=\"entry-syllable\" title=\"Suku kata\">(" & htmlEsc(syllable) & ")</span>"
      else: ""
    html = html &
      "<article class=\"entry-card\" data-id=\"" & id & "\" role=\"article\">" &
        "<div class=\"entry-head\">" &
          "<span class=\"entry-lema\">" & htmlEsc(word.removeNumberTag()) & "</span>" &
          syllableHtml &
          kindBadgeHtml(kind) &
        "</div>" &
        renderEntry(word, kind, id, sensesJson) &
      "</article>"
  return html

proc searchById(id: cstring): (cstring, cstring) =
  let rows = getResultRows(dbQuery("""
    SELECT id, nilai, word, kind FROM entries WHERE id=?""", id))
  if rows.len == 0:
    return ("", "<div class=\"not-found\"><div class=\"nf-icon\">∅</div><p>Entri tidak ditemukan.</p></div>")
  let word = rows[0][2]
  let html = "<div class=\"result-header\"><span class=\"result-label\">Hasil untuk</span>" &
    "<h2 class=\"result-word\">" & htmlEsc(word.removeNumberTag()) & "</h2></div>" & buildResultCards(rows)
  return (word, html)

proc searchExact(query: cstring): (cstring, bool) =
  let norm  = normalizeWord(query)
  let fnorm = fuzzyNormWord(query)
  var rows = getResultRows(dbQuery("""
    SELECT id, nilai, word, kind FROM entries WHERE nilai=?""", norm))
  if rows.len == 0 and fnorm != norm:
    rows = getResultRows(dbQuery("""
      SELECT id, nilai, word, kind FROM entries WHERE nilai_norm=?""", fnorm))
  if rows.len == 0:
    return ("<div class=\"not-found\"><div class=\"nf-icon\">∅</div>" &
      "<p>Kata <strong>&ldquo;" & htmlEsc(query) & "&rdquo;</strong> tidak ditemukan dalam KBBI.</p>" &
      "<p class=\"nf-hint\">Coba mode <em>Awalan</em> atau <em>Teks penuh</em>.</p></div>", false)
  return ("<div class=\"result-header\"><span class=\"result-label\">Hasil untuk</span>" &
    "<h2 class=\"result-word\">" & htmlEsc(rows[0][2].removeNumberTag()) & "</h2></div>" & buildResultCards(rows), true)

proc searchPrefix(query: cstring): (cstring, bool) =
  let norm  = normalizeWord(query)
  let fnorm = fuzzyNormWord(query)
  let nextNorm  = nextChar(norm)
  let nextFnorm = nextChar(fnorm)

  var rows: seq[seq[cstring]] = @[]
  var seenIds: seq[cstring] = @[]

  let pass1 = getResultRows(dbQuery2("""
      SELECT id, nilai, word, kind FROM entries
      WHERE nilai >= ? AND nilai < ? ORDER BY nilai LIMIT """ & cstring($RESULT_LIMIT_PREFIX),
      norm, nextNorm))
  for row in pass1:
    if row.len == 0: continue
    let rid = row[0]
    if not seenIds.contains(rid):
      seenIds.add(rid)
      rows.add(row)

  let pass2 = getResultRows(dbQuery2("""
      SELECT id, nilai, word, kind FROM entries
      WHERE nilai_norm >= ? AND nilai_norm < ? ORDER BY nilai LIMIT """ & cstring($RESULT_LIMIT_PREFIX),
      fnorm, nextFnorm))
  for row in pass2:
    if row.len == 0: continue
    let rid = row[0]
    if not seenIds.contains(rid):
      seenIds.add(rid)
      rows.add(row)

  if rows.len == 0:
    return ("<div class=\"not-found\"><div class=\"nf-icon\">∅</div>" &
      "<p>Tidak ada kata dengan awalan <strong>&ldquo;" & htmlEsc(query) & "&rdquo;</strong>.</p></div>", false)
  if rows.len == 1:
    return ("<div class=\"result-header\"><span class=\"result-label\">Hasil untuk</span>" &
      "<h2 class=\"result-word\">" & htmlEsc(rows[0][2].removeNumberTag()) & "</h2></div>" & buildResultCards(rows), true)
  var listHtml: cstring = cstring(
    "<div class=\"result-header\"><span class=\"result-label\">Ditemukan</span>" &
    "<h2 class=\"result-word\">" & $rows.len & " kata</h2></div><div class=\"word-list\" role=\"list\">")
  for row in rows:
    listHtml = listHtml &
      "<button class=\"word-chip\" data-action=\"search-id\" data-id=\"" & row[0] & "\" role=\"listitem\" aria-label=\"" & htmlEsc(row[2]) & "\">" &
      htmlEsc(row[2]) & kindBadgeHtml(row[3]) & "</button>"
  return (listHtml & "</div>", true)

proc searchFTS(query: cstring): cstring =
  var safeQuery: cstring
  {.emit: [safeQuery, " = '\"' + String(", query, ").replace(/\"/g, '\"\"') + '\"';"].}
  var res: JsObject
  var ftsErr: cstring = ""
  {.emit: ["""
    try {
      """, res, """ = """, db, """.exec(
        "SELECT e.id, e.nilai, e.word, e.kind FROM entries_fts f " +
        "JOIN entries e ON e.id = f.rowid WHERE entries_fts MATCH ? ORDER BY rank LIMIT """, cstring($RESULT_LIMIT_FTS), """",
        [""", safeQuery, """]);
    } catch(e) { """, ftsErr, """ = String(e.message || e); }
  """].}
  if $ftsErr != "":
    return "<div class=\"not-found\"><div class=\"nf-icon\">∅</div>" &
      "<p>Kueri FTS tidak valid: <em>" & htmlEsc(ftsErr) & "</em></p></div>"
  let rows = getResultRows(res)
  if rows.len == 0:
    return "<div class=\"not-found\"><div class=\"nf-icon\">∅</div>" &
      "<p>Tidak ada hasil FTS untuk <strong>&ldquo;" & htmlEsc(query) & "&rdquo;</strong>.</p></div>"
  return cstring("<div class=\"result-header\"><span class=\"result-label\">FTS —</span>" &
    "<h2 class=\"result-word\">" & $rows.len & " hasil</h2></div>") & buildResultCards(rows)

proc katColName(jenis: cstring): cstring =
  case $jenis
  of "kelas":  return "pos"
  of "bahasa": return "bahasa"
  of "bidang": return "bidang"
  of "ragam":  return "ragam"
  of "jenis":  return "markers"
  else:        return jenis

proc searchKat(jenis, nilai, query: cstring): cstring =
  if db.isNil:
    return DB_LOADING_ERROR
  let col = katColName(jenis)
  let norm  = normalizeWord(query)
  let fnorm = fuzzyNormWord(query)
  let nextNorm  = nextChar(norm)
  let nextFnorm = nextChar(fnorm)
  let hasQuery = $query != ""
  let katClause: cstring = "(',' || s." & col & " || ',') LIKE '%,' || ? || ',%'"
  let wordClause: cstring =
    if hasQuery:
      " AND (e.nilai >= ? AND e.nilai < ? OR e.nilai_norm >= ? AND e.nilai_norm < ?)"
    else: ""
  let likeQ: cstring =
    "SELECT DISTINCT e.id, e.nilai, e.word, e.kind FROM entries e " &
    "JOIN senses s ON e.id = s.entry_id " &
    "WHERE " & katClause & wordClause &
    " ORDER BY e.nilai LIMIT " & cstring($RESULT_LIMIT_KAT)
  let countQ: cstring =
    "SELECT COUNT(DISTINCT e.id) FROM entries e " &
    "JOIN senses s ON e.id = s.entry_id " &
    "WHERE " & katClause & wordClause
  var res: JsObject
  if hasQuery:
    {.emit: [res, " = ", db, ".exec(", likeQ, ", [", nilai, ",", norm, ",", nextNorm, ",", fnorm, ",", nextFnorm, "]);"].}
  else:
    {.emit: [res, " = ", db, ".exec(", likeQ, ", [", nilai, "]);"].}
  let rows = getResultRows(res)
  var countRes: JsObject
  if hasQuery:
    {.emit: [countRes, " = ", db, ".exec(", countQ, ", [", nilai, ",", norm, ",", nextNorm, ",", fnorm, ",", nextFnorm, "]);"].}
  else:
    {.emit: [countRes, " = ", db, ".exec(", countQ, ", [", nilai, "]);"].}
  var total: cstring = "0"
  let countRows = getResultRows(countRes)
  if countRows.len > 0 and countRows[0].len > 0:
    total = countRows[0][0]

  if rows.len == 0:
    return "<div class=\"not-found\"><div class=\"nf-icon\">∅</div>" &
      "<p>Tidak ada kata dengan " & htmlEsc(jenis) & " = <strong>" & htmlEsc(nilai) & "</strong>.</p></div>"

  let desc = katGet(jenis, nilai)
  let titleLabel: cstring = if desc != nilai: htmlEsc(nilai) & " — " & htmlEsc(desc) else: htmlEsc(nilai)

  var listHtml: cstring =
    "<div class=\"result-header\">" &
      "<span class=\"result-label\">" & htmlEsc(jenis) & "</span>" &
      "<h2 class=\"result-word\">" & titleLabel.removeNumberTag() & "</h2>" &
    "</div>" &
    "<div class=\"word-list\" role=\"list\">"
  for row in rows:
    listHtml = listHtml &
      "<button class=\"word-chip\" data-action=\"search-id\" data-id=\"" & row[0] & "\" role=\"listitem\" aria-label=\"" & htmlEsc(row[2]) & "\">" &
      htmlEsc(row[2]) & kindBadgeHtml(row[3]) & "</button>"
  listHtml = listHtml & "</div>"
  listHtml = listHtml &
    "<p style='margin-top:0.75rem;font-size:0.8rem;color:var(--text-muted)'>" &
    total & " kata ditemukan" &
    (if ($total).parseInt != rows.len: ", menampilkan " & cstring($rows.len) else: "") &
    "</p>"
  return listHtml

proc searchList(jenis: cstring): cstring =
  if db.isNil:
    return DB_LOADING_ERROR
  let tableName: cstring = "kategori_" & jenis
  let listQ: cstring =
    "SELECT k.nilai, k.desc, COALESCE(c.cnt, 0) AS cnt " &
    "FROM " & tableName & " k " &
    "LEFT JOIN kategori_counts c ON c.jenis = '" & jenis & "' AND c.nilai = k.nilai " &
    "ORDER BY cnt DESC"
  var res: JsObject
  {.emit: [res, " = ", db, ".exec(", listQ, ");"].}
  let rows = getResultRows(res)
  if rows.len == 0:
    return "<div class=\"not-found\"><div class=\"nf-icon\">∅</div>" &
      "<p>Tidak ada kategori untuk <strong>" & htmlEsc(jenis) & "</strong>.</p></div>"
 
 
  var html: cstring =
    "<div class=\"result-header\">" &
      "<span class=\"result-label\">Kategori</span>" &
      "<h2 class=\"result-word\">" & htmlEsc(jenis.removeNumberTag()) & "</h2>" &
    "</div>" &
    "<div class=\"word-list\" role=\"list\">"
  for row in rows:
    if row.len < 3: continue
    let nilai = row[0]
    let desc  = row[1]
    let cnt   = row[2]
    html = html &
      "<button class=\"word-chip\" data-action=\"filter-kat\" data-jenis=\"" & htmlEsc(jenis) & "\" data-nilai=\"" & htmlEsc(nilai) & "\"" &
      " title=\"" & htmlEsc(desc) & "\" role=\"listitem\" aria-label=\"" & htmlEsc(nilai) & ": " & htmlEsc(cnt) & " kata\">" &
      htmlEsc(nilai) &
      "<span class=\"kat-count\">(" & htmlEsc(cnt) & ")</span>" &
      "</button>"
  return html & "</div>"

proc getKatFilter(): cstring =
  let el = getById("kat-filter-input")
  if el.isNil: return ""
  return cstring(($getValue(el)).strip())

proc updateKatFilterRow(mode: cstring) =
  let row = getById("kat-filter-row")
  let lbl = getById("kat-filter-label")
  if row.isNil or lbl.isNil: return
  let modeStr = $mode
  if modeStr.startsWith("kat-"):
    let jenis = modeStr[4..^1]
    let labelText: cstring = case jenis
      of "kelas":  "kelas kata"
      of "bahasa": "bahasa"
      of "bidang": "bidang"
      of "ragam":  "ragam"
      else:        cstring(jenis)
    setInnerHTML(lbl, labelText)
    row.classList.remove("hidden")
    let filterInp = getById("kat-filter-input")
    if not filterInp.isNil: focusEl(filterInp)
  else:
    row.classList.add("hidden")

proc getMode(): cstring =
  let sel = getById("search-mode")
  if sel.isNil: return "auto"
  return getValue(sel)

proc doSearchWith(query: cstring, mode: cstring) =
  if db.isNil:
    setText("result", DB_LOADING_ERROR)
    setClass("result", "hidden", false)
    return
  setLoading(false)
  let res = getById("result")
  if res.isNil: return
  if query != "" and not ($mode).startsWith("list-"):
    updateHistory(query)
  var html: cstring
  case $mode
  of "fts":         html = searchFTS(query)
  of "prefix":
    let (prefHtml, _) = searchPrefix(query)
    html = prefHtml
  of "kat-kelas":   html = searchKat("kelas",  getKatFilter(), query)
  of "kat-bahasa":  html = searchKat("bahasa", getKatFilter(), query)
  of "kat-bidang":  html = searchKat("bidang", getKatFilter(), query)
  of "kat-ragam":   html = searchKat("ragam",  getKatFilter(), query)
  of "list-kelas":  html = searchList("kelas")
  of "list-bahasa": html = searchList("bahasa")
  of "list-bidang": html = searchList("bidang")
  of "list-ragam":  html = searchList("ragam")
  else:
    let (exactHtml, found) = searchExact(query)
    if found:
      html = exactHtml
    else:
      let (prefixHtml, pfound) = searchPrefix(query)
      html = if pfound: prefixHtml else: exactHtml
  setInnerHTML(res, html)
  res.classList.remove("hidden")
  smoothScroll(res)

proc doSearch*() {.exportc.} =
  let mode = getMode()
  let inp = getById("search-input")
  if inp.isNil: return
  let v = cstring(($getValue(inp)).strip())
  if v == "" and not ($mode).startsWith("list-"): return
  setLoading(true)
  doSearchWith(v, mode)

proc nimSearch*(word: cstring) {.exportc.} =
  let inp = getById("search-input")
  if not inp.isNil: setValue(inp, word)
  let sel = getById("search-mode")
  if not sel.isNil: setValue(sel, "auto")
  updateKatFilterRow("auto")
  setLoading(true)
  doSearchWith(word, "auto")

proc nimSearchById*(id: cstring) {.exportc.} =
  setLoading(false)
  let res = getById("result")
  if res.isNil: return
  let (word, html) = searchById(id)
  if word != "":
    let inp = getById("search-input")
    if not inp.isNil: setValue(inp, word)
    updateHistory(word)
  setInnerHTML(res, html)
  res.classList.remove("hidden")
  smoothScroll(res)

proc nimKat*(jenis, nilai: cstring) {.exportc.} =
  let mode: cstring = "kat-" & jenis
  let sel = getById("search-mode")
  if not sel.isNil: setValue(sel, mode)
  updateKatFilterRow(mode)
  let katInp = getById("kat-filter-input")
  if not katInp.isNil: setValue(katInp, nilai)
  let inp = getById("search-input")
  if not inp.isNil: setValue(inp, "")
  let res = getById("result")
  if res.isNil: return
  if db.isNil:
    setText("result", DB_LOADING_ERROR)
    setClass("result", "hidden", false)
    return
  let html = searchKat(jenis, nilai, "")
  setInnerHTML(res, html)
  res.classList.remove("hidden")
  smoothScroll(res)

proc handleResultClick(e: Event) =
  let target = cast[Element](e.target)
  if target.isNil: return
  let action = target.getAttribute("data-action")
  if action == "search".cstring:
    let query = target.getAttribute("data-query")
    if query != "": nimSearch(query)
  elif action == "search-id".cstring:
    let id = target.getAttribute("data-id")
    if id != "": nimSearchById(id)
  elif action == "filter-kat".cstring:
    let jenis = target.getAttribute("data-jenis")
    let nilai = target.getAttribute("data-nilai")
    if jenis != "" and nilai != "": nimKat(jenis, nilai)

proc initCustomDropdown() =
  let cpSelect = getById("cp-select")
  let panel    = getById("cp-select-panel")
  let labelEl  = getById("cp-select-label")
  let nativeEl = getById("search-mode")
  if cpSelect.isNil or panel.isNil or labelEl.isNil or nativeEl.isNil: return

  let nodeList = querySelectorAll(panel, ".cp-select__option")
  var allOpts: seq[Element] = @[]
  let optCount = jsLength(nodeList)
  for i in 0 ..< optCount:
    allOpts.add(cast[Element](jsItem(nodeList, i)))

  const LABELS: array[11, (cstring, cstring)] = [
    ("auto",       "Otomatis"),
    ("prefix",     "Awalan"),
    ("fts",        "Teks penuh"),
    ("kat-kelas",  "Kelas kata"),
    ("kat-bahasa", "Bahasa"),
    ("kat-bidang", "Bidang"),
    ("kat-ragam",  "Ragam"),
    ("list-kelas", "Daftar kelas"),
    ("list-bahasa","Daftar bahasa"),
    ("list-bidang","Daftar bidang"),
    ("list-ragam", "Daftar ragam"),
  ]

  proc labelFor(value: cstring): cstring =
    for i in 0 ..< LABELS.len:
      if LABELS[i][0] == value: return LABELS[i][1]
    return value

  var highlightedIdx = 0
  var selectedIdx    = 0

  proc setHighlight(idx: int, scroll: bool) =
    let clamped = max(0, min(idx, allOpts.len - 1))
    highlightedIdx = clamped
    for i in 0 ..< allOpts.len:
      let o = allOpts[i]
      if i == clamped: o.classList.add("cp-opt--highlighted")
      else: o.classList.remove("cp-opt--highlighted")
    if scroll: scrollIntoViewNearest(allOpts[clamped])

  proc closePanel() =
    cpSelect.classList.remove("is-open")
    setAttribute(cpSelect, "aria-expanded", "false")
    for i in 0 ..< allOpts.len:
      allOpts[i].classList.remove("cp-opt--highlighted")

  proc openPanel() =
    cpSelect.classList.add("is-open")
    setAttribute(cpSelect, "aria-expanded", "true")
    setHighlight(selectedIdx, true)

  proc pick(value: cstring) =
    var idx = -1
    for i in 0 ..< allOpts.len:
      if dataValue(allOpts[i]) == value:
        idx = i
        break
    selectedIdx = if idx >= 0: idx else: 0
    for i in 0 ..< allOpts.len:
      let o = allOpts[i]
      if i == selectedIdx: o.classList.add("cp-select__option--selected")
      else: o.classList.remove("cp-select__option--selected")
    elTextContent(labelEl, labelFor(value))
    setValue(nativeEl, value)
    dispatchChange(nativeEl)
    closePanel()

  addClickListener(cpSelect, proc(ev: Event) =
    let opt = closestOpt(cast[Element](ev.target))
    if not opt.isNil:
      let v = dataValue(opt)
      pick(v)
      return
    if cpSelect.classList.contains("is-open"): closePanel()
    else: openPanel()
  )

  addClickListener(document.body, proc(ev: Event) =
    if not contains(cpSelect, cast[Element](ev.target)): closePanel()
  )

  addKbListener(cpSelect, proc(ev: KeyboardEvent) =
    let isOpen = cpSelect.classList.contains("is-open")
    let key = ev.key
    if key == "Escape":
      ev.preventDefault()
      closePanel()
    elif key == "Enter" or key == " ":
      ev.preventDefault()
      if not isOpen: openPanel()
      else: pick(dataValue(allOpts[highlightedIdx]))
    elif key == "ArrowDown":
      ev.preventDefault()
      if not isOpen: openPanel()
      else: setHighlight(highlightedIdx + 1, true)
    elif key == "ArrowUp":
      ev.preventDefault()
      if not isOpen: openPanel()
      else: setHighlight(highlightedIdx - 1, true)
  )

  setGlobalCpSelect(pick)


proc loadDatabase() {.async.} =
  setText("load-status", "Memulai sql.js…")
  setClass("load-overlay", "hidden", false)
  dbLoadError = ""
  try:
    var sqlCfg: JsObject
    {.emit: [sqlCfg, " = {locateFile: function(f){return 'https://cdn.jsdelivr.net/npm/sql.js-fts5@1.4.0/dist/' + f;}}"].}
    let SQL = await initSqlJs(sqlCfg)
    initWordCache()
    setText("load-status", "Mengunduh kbbi.db… (0%)")
    var resp: JsObject
    {.emit: ["""
      try {
        const CACHE_NAME = '""", CACHE_KEY, """';
        const URL = 'kbbi.db';
        const loadBar = document.querySelector('.load-bar');
        const loadStatus = document.getElementById('load-status');

        const cache = await caches.open(CACHE_NAME);
        let response = await cache.match(URL);
        let fromCache = !!response;

        if (!response) {
          const fetched = await fetch(URL, { cache: 'no-store' });
          if (!fetched.ok) {
            throw new Error('kbbi.db fetch failed: ' + fetched.status);
          }
          
          // Track download progress
          const contentLength = fetched.headers.get('content-length');
          if (contentLength) {
            const total = parseInt(contentLength, 10);
            const reader = fetched.body.getReader();
            let loaded = 0;
            const chunks = [];
            
            try {
              while (true) {
                const {done, value} = await reader.read();
                if (done) break;
                chunks.push(value);
                loaded += value.length;
                const percent = Math.min(100, Math.round((loaded / total) * 100));
                if (loadBar) loadBar.style.width = percent + '%';
                if (loadStatus && percent !== 100) loadStatus.textContent = 'Mengunduh kbbi.db… (' + percent + '%)';
                if (loadStatus && percent === 100) loadStatus.textContent = 'Menginisialisasi database...';
              }
            } finally {
              reader.releaseLock();
            }
            
            // Reconstruct response from chunks
            const blob = new Blob(chunks);
            response = new Response(blob);
          } else {
            response = fetched;
          }
          
          // Cache the downloaded file
          await cache.put(URL, response.clone());
        } else {
          // Loaded from cache — show 100%
          if (loadBar) loadBar.style.width = '100%';
          if (loadStatus) loadStatus.textContent = 'Memuat dari cache… (100%)';
        }

        """, resp, """ = response;
      } catch (e) {
        // Fallback fetch without progress tracking
        """, resp, """ = await fetch('kbbi.db');
        const loadBar = document.querySelector('.load-bar');
        if (loadBar) loadBar.style.width = '100%';
      }
    """].}
    let buf  = await arrayBuffer(resp)
    let u8   = uint8Array(buf)
    setText("load-status", "Membuka database…")
    db = newDb(SQL, u8)
    loadKategori()
    setClass("load-overlay", "hidden", true)
    let inp = getById("search-input")
    if not inp.isNil: focusEl(inp)
  except:
    dbLoadError = "Gagal memuat database"
    setText("load-status", "⚠ Gagal memuat. Periksa koneksi atau cache. <a href='javascript:location.reload()' style='color:var(--accent)'>Muat ulang</a>")


window.onload = proc(e: Event) =
  let inp    = getById("search-input")
  let btn    = getById("search-btn")
  let sel    = getById("search-mode")
  let katInp = getById("kat-filter-input")
  let res    = getById("result")
  
  loadHistoryFromStorage()
  renderHistory()
  initCustomDropdown()
  
  if not inp.isNil:
    addKbListener(inp, proc(ev: KeyboardEvent) =
      if ev.keyCode == 13 or ev.key == "Enter": doSearch()
    )
  if not katInp.isNil:
    addKbListener(katInp, proc(ev: KeyboardEvent) =
      if ev.keyCode == 13 or ev.key == "Enter": doSearch()
    )
  if not btn.isNil:
    addClickListener(btn, proc(ev: Event) = doSearch())
  if not sel.isNil:
    addChangeListener(sel, proc(ev: Event) = updateKatFilterRow(getMode()))
  
  if not res.isNil:
    addClickListener(res, handleResultClick)
  
  let clearBtn = getById("clear-history-btn")
  if not clearBtn.isNil:
    addClickListener(clearBtn, proc(ev: Event) = clearHistory())
  
  let histList = getById("history-list")
  if not histList.isNil:
    addClickListener(histList, handleResultClick)
  
  discard loadDatabase()