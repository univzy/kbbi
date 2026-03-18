import std/[dom, jsffi, asyncjs, strutils]
import kbbi/[version]

const cacheKey = "kbbi_cache_vi_" & KbbiVersion

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

proc normalizeWord(s: cstring): cstring {.importjs: "(#).toLowerCase()".}

proc fuzzyNormWord(s: cstring): cstring {.importjs: """(function(s){
  return s.toLowerCase().replace(/[^a-z0-9\u0080-\uffff]/g,'');
})(#)""".}

proc replaceHeadword(example, headword: cstring): cstring {.importjs: """
  (function(ex, hw){ return ex.replace(/--|~/g, hw); })(#, #)
""".}

proc htmlEsc(s: cstring): cstring {.importjs: """
  (function(s){ return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); })(#)
""".}

proc jsStrEsc(s: cstring): cstring {.importjs: """
  (function(s){ return String(s||'').replace(/\\/g,'\\\\').replace(/'/g,"\\'").replace(/"/g,'\\"'); })(#)
""".}

var db: JsObject = nil
var searchHistory: seq[cstring] = @[]

proc nextChar(s: cstring): cstring {.importjs: """
  (function(s){ return s.length>0 ? s.slice(0,-1)+String.fromCharCode(s.charCodeAt(s.length-1)+1) : '\xff'; })(#)
""".}

var kategoriMap: JsObject = nil

proc katGet(jenis, nilai: cstring): cstring =
  if kategoriMap.isNil: return nilai
  var desc: cstring = ""
  let key = jenis & ":" & nilai
  {.emit: [desc, " = ", kategoriMap, "[", key, "] || '';"].}
  if desc == "": return nilai
  return desc

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

proc updateHistory(word: cstring) =
  for h in searchHistory:
    if h == word: return
  searchHistory.insert(word, 0)
  if searchHistory.len > 8: searchHistory = searchHistory[0..7]
  var html: cstring = ""
  for h in searchHistory:
    html = html & "<button class='hist-item' onclick='nimSearch(\"" & jsStrEsc(h) & "\")'>" & htmlEsc(h) & "</button>"
  setText("history-list", html)
  setClass("history-section", "hidden", false)

proc badgeWithTooltip(cls, code, jenis: cstring): cstring =
  let desc = katGet(jenis, code)
  let title: cstring = if desc != code: " title='" & htmlEsc(desc) & "'" else: ""
  return "<span class='badge " & cls & "'" & title & ">" & htmlEsc(code) & "</span>"

proc kindBadgeHtml(kind: cstring): cstring =
  case $kind
  of "foreign":     return "<span class='kind-badge foreign' title='Kata/ungkapan asing'>asing</span>"
  of "phrase":      return "<span class='kind-badge phrase' title='Frasa'>frasa</span>"
  of "nonstandard": return "<span class='kind-badge nonstandard' title='Ejaan tidak baku'>tidak baku</span>"
  of "alias":       return "<span class='kind-badge alias' title='Alias'>alias</span>"
  of "redirect":    return "<span class='kind-badge redirect' title='Merujuk ke entri lain'>lihat</span>"
  of "group":       return "<span class='kind-badge group' title='Beberapa entri berbagi satu kunci'>grup</span>"
  else:             return ""

proc markerBadge(m: cstring): cstring =
  case $m
  of "ki":   return "<span class='badge marker' title='Kiasan (figuratif/idiom)'>ki</span>"
  of "sing": return "<span class='badge marker' title='Singkatan'>sing</span>"
  of "akr":  return "<span class='badge marker' title='Akronim'>akr</span>"
  of "ukp":  return "<span class='badge marker' title='Ungkapan (ekspresi asing)'>ukp</span>"
  else:      return "<span class='badge marker'>" & htmlEsc(m) & "</span>"

proc xrefGroupLabel(kind: cstring): cstring =
  case $kind
  of "baku":       return "<span class='xref-kind baku' title='Bentuk baku'>bentuk baku</span>"
  of "dasar":      return "<span class='xref-kind dasar' title='Kata dasar'>kata dasar</span>"
  of "lihat":      return "<span class='xref-kind lihat' title='Lihat juga'>lihat juga</span>"
  of "turunan":    return "<span class='xref-kind turunan' title='Kata turunan'>kata turunan</span>"
  of "gabungan":   return "<span class='xref-kind gabungan' title='Kata gabungan'>kata gabungan</span>"
  of "peribahasa": return "<span class='xref-kind peribahasa' title='Peribahasa'>peribahasa</span>"
  else:            return "<span class='xref-kind tidak-baku' title='Bentuk tidak baku'>bentuk tidak baku</span>"

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
  var word: cstring = ""
  let idStr = cstring($id)
  {.emit: ["""try {
    var _r=""", db, """.exec("SELECT word FROM entries WHERE id=?",[""", idStr, """]);
    if(_r.length>0&&_r[0].values.length>0) """, word, """=String(_r[0].values[0][0]||'');
  } catch(e) {}"""].}
  return word

proc fetchEntrySenses(entryId: cstring, word: cstring, kind: cstring): cstring =
  result = "[]"
  {.emit: ["""
  try {
    var entryId = """, entryId, """;
    var isGroup = (""", kind, """ === 'group');

    // 1. All senses for this entry
    var sRows = """, db, """.exec(
      'SELECT id,entry_word,entry_kind,' +
      'number,pos,bahasa,bidang,ragam,markers,text,' +
      'altForm,altText,latin,abbrev,link,chem ' +
      'FROM senses WHERE entry_id=? ORDER BY id', [entryId]);
    if (!sRows.length || !sRows[0].values.length) { """, result, """ = '[]'; return; }

    var senseRows = sRows[0].values;
    var senseIds = senseRows.map(function(r){ return r[0]; });

    // 2. All examples for these senses in one query
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

    // 3. All xrefs for these senses in one query
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

    // 4. All xref_groups for these senses in one query
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

proc renderXrefs(xrArr: JsObject): cstring =
  if xrArr.isNil or jsLength(xrArr) == 0: return ""
  var links: seq[cstring] = @[]
  for i in 0..<jsLength(xrArr):
    let id = jsInt(jsItem(xrArr, i))
    if id == 0: continue
    let w = lookupWordById(id)
    if w != "" and w != "null" and w != "undefined":
      links.add("<button class='xref-link' onclick='nimSearchById(" & cstring($id) & ")'>" & htmlEsc(w) & "</button>")
    else:
      links.add("<span class='xref-id'>#" & cstring($id) & "</span>")
  if links.len == 0: return ""
  var html: cstring = "<div class='xrefs plain'>"
  html = html & xrefGroupLabel("")
  for lk in links: html = html & lk
  return html & "</div>"

proc renderXrefGroups(xgArr: JsObject): cstring =
  if xgArr.isNil or jsLength(xgArr) == 0: return ""
  var html: cstring = ""
  for i in 0..<jsLength(xgArr):
    let grp  = jsItem(xgArr, i)
    let kind = jsStr(jsGet(grp, "kind"))
    let refs = jsGet(grp, "refs")
    if refs.isNil or jsLength(refs) == 0: continue
    var links: seq[cstring] = @[]
    for j in 0..<jsLength(refs):
      let id = jsInt(jsItem(refs, j))
      if id == 0: continue
      let w = lookupWordById(id)
      if w != "" and w != "null" and w != "undefined":
        links.add("<button class='xref-link' onclick='nimSearchById(" & cstring($id) & ")'>" & htmlEsc(w) & "</button>")
      else:
        links.add("<span class='xref-id'>#" & cstring($id) & "</span>")
    if links.len == 0: continue
    html = html & "<div class='xref-group'>" & xrefGroupLabel(kind)
    for lk in links: html = html & lk
    html = html & "</div>"
  return html

proc renderSense(s: JsObject, headword: cstring): cstring =
  let num = jsStr(jsGet(s, "number"))
  let p   = jsStr(jsGet(s, "pos"))
  let bh  = jsStr(jsGet(s, "bahasa"))
  let bd  = jsStr(jsGet(s, "bidang"))
  let r   = jsStr(jsGet(s, "ragam"))
  let m   = jsStr(jsGet(s, "markers"))
  let t   = jsStr(jsGet(s, "text"))
  let af  = jsStr(jsGet(s, "alt_form"))
  let at  = jsStr(jsGet(s, "alt_text"))
  let l   = jsStr(jsGet(s, "latin"))
  let ab  = jsStr(jsGet(s, "abbrev"))
  let lk  = jsStr(jsGet(s, "link"))
  let ch  = jsStr(jsGet(s, "chem"))

  var numHtml: cstring = ""
  if num != "" and num != "null" and num != "undefined":
    numHtml = "<span class='sense-num'>" & htmlEsc(num) & "</span>"

  var badges: cstring = ""
  if p  != "": badges = badges & badgeWithTooltip("kelas",  p,  "kelas")
  if bh != "": badges = badges & badgeWithTooltip("bahasa", bh, "bahasa")
  if bd != "": badges = badges & badgeWithTooltip("bidang", "[" & bd & "]", "bidang")
  if r  != "": badges = badges & badgeWithTooltip("ragam",  r,  "ragam")
  if m  != "":
    let ms = ($m).split(",")
    for mk in ms:
      let mkc = mk.strip()
      if mkc != "": badges = badges & markerBadge(cstring(mkc))

  var body: cstring = ""
  if t  != "": body = body & "<span class='def-text'>" & htmlEsc(t) & "</span>"
  if ab != "": body = body & " <span class='def-abbrev' title='Kepanjangan singkatan'>(" & htmlEsc(ab) & ")</span>"
  if af != "":
    body = body & " <span class='def-note'>bentuk tidak baku: <button class='inline-link' onclick='nimSearch(\"" & htmlEsc(af) & "\")'>" & htmlEsc(af) & "</button></span>"
  if at != "":
    body = body & " <span class='def-note'>lihat: <button class='inline-link' onclick='nimSearch(\"" & htmlEsc(at) & "\")'>" & htmlEsc(at) & "</button></span>"
  if lk != "":
    body = body & " <span class='def-note'>= <button class='inline-link' onclick='nimSearch(\"" & htmlEsc(lk) & "\")'>" & htmlEsc(lk) & "</button></span>"
  if l  != "": body = body & " <span class='def-latin'><em>" & htmlEsc(l) & "</em></span>"
  if ch != "": body = body & " <span class='def-chem'>" & htmlEsc(ch) & "</span>"

  var exHtml: cstring = ""
  let exArr = jsGet(s, "examples")
  if not exArr.isNil and jsLength(exArr) > 0:
    exHtml = "<ul class='examples'>"
    for i in 0..<jsLength(exArr):
      let raw = jsStr(jsItem(exArr, i))
      let ex  = replaceHeadword(raw, headword)
      exHtml = exHtml & "<li>" & htmlEsc(ex) & "</li>"
    exHtml = exHtml & "</ul>"

  let xrHtml = renderXrefs(jsGet(s, "xrefs"))
  let xgHtml = renderXrefGroups(jsGet(s, "xref_groups"))

  return "<li class='sense-item'>" &
    numHtml &
    "<div class='sense-right'>" &
      "<div class='sense-meta'>" & badges & "</div>" &
      "<div class='sense-body'>" & body & exHtml & xrHtml & xgHtml & "</div>" &
    "</div>" &
    "</li>"

proc renderRedirectCard(word, kind, entryId: cstring): cstring =
  var targets: cstring = ""
  let atRows = getResultRows(dbQuery("""
    SELECT altText FROM senses WHERE entry_id=? AND altText != '' LIMIT 1""", entryId))
  if atRows.len > 0 and atRows[0].len > 0 and atRows[0][0] != "":
    let at = atRows[0][0]
    targets = "<button class='xref-link prominent' onclick='nimSearch(\"" & htmlEsc(at) & "\")'>" & htmlEsc(at) & " →</button>"
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
        if w != "" and w != "null" and w != "undefined":
          links = links & "<button class='xref-link' onclick='nimSearchById(" & id & ")'>" & htmlEsc(w) & "</button>"
      if links != "": targets = links

  let lbl: cstring = if $kind == "alias": "merupakan alias dari" else: "merujuk ke"
  return "<div class='redirect-card'>" &
    "<span class='redirect-icon'>↪</span>" &
    "<div class='redirect-body'>" &
      "<span class='redirect-word'>" & htmlEsc(word) & "</span>" &
      "<span class='redirect-label'> " & lbl & " </span>" &
      targets &
    "</div></div>"

proc renderEntry(word, kind, entryId: cstring): cstring =
  let kindStr = $kind
  if kindStr == "redirect" or kindStr == "alias":
    return renderRedirectCard(word, kind, entryId)

  let sensesJson = fetchEntrySenses(entryId, word, kind)
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
    for i in 0..<jsLength(variants):
      let v  = jsItem(variants, i)
      let vw = jsStr(jsGet(v, "word"))
      let vk = jsStr(jsGet(v, "kind"))
      let ss = jsGet(v, "senses")
      let displayWord: cstring = if vw != "" and vw != "null": vw else: word
      html = html & "<div class='variant'>" &
        "<div class='variant-head'><em>" & htmlEsc(displayWord) & "</em>" &
        kindBadgeHtml(vk) & "</div>" &
        "<ol class='sense-list'>"
      if not ss.isNil:
        for j in 0..<jsLength(ss):
          html = html & renderSense(jsItem(ss, j), displayWord)
      html = html & "</ol></div>"
  else:
    html = "<ol class='sense-list'>"
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

    html = html &
      "<div class='entry-card' data-id='" & id & "'>" &
        "<div class='entry-head'>" &
          "<span class='entry-lema'>" & htmlEsc(word) & "</span>" &
          kindBadgeHtml(kind) &
        "</div>" &
        renderEntry(word, kind, id) &
      "</div>"
  return html

proc searchById(id: cstring): (cstring, cstring) =
  let rows = getResultRows(dbQuery("""
    SELECT id, nilai, word, kind FROM entries WHERE id=?""", id))
  if rows.len == 0:
    return ("", "<div class='not-found'><div class='nf-icon'>∅</div><p>Entri tidak ditemukan.</p></div>")
  let word = rows[0][2]
  let html = "<div class='result-header'><span class='result-label'>Hasil untuk</span>" &
    "<h2 class='result-word'>" & htmlEsc(word) & "</h2></div>" & buildResultCards(rows)
  return (word, html)

proc searchExact(query: cstring): cstring =
  let norm  = normalizeWord(query)
  let fnorm = fuzzyNormWord(query)
  var rows = getResultRows(dbQuery("""
    SELECT id, nilai, word, kind FROM entries WHERE nilai=?""", norm))
  if rows.len == 0 and fnorm != norm:
    rows = getResultRows(dbQuery("""
      SELECT id, nilai, word, kind FROM entries WHERE nilai_norm=?""", fnorm))
  if rows.len == 0:
    return "<div class='not-found'><div class='nf-icon'>∅</div>" &
      "<p>Kata <strong>&ldquo;" & htmlEsc(query) & "&rdquo;</strong> tidak ditemukan dalam KBBI.</p>" &
      "<p class='nf-hint'>Coba mode <em>Awalan</em> atau <em>Teks penuh</em>.</p></div>"
  return "<div class='result-header'><span class='result-label'>Hasil untuk</span>" &
    "<h2 class='result-word'>" & htmlEsc(rows[0][2]) & "</h2></div>" & buildResultCards(rows)

proc searchPrefix(query: cstring): cstring =
  let norm  = normalizeWord(query)
  let fnorm = fuzzyNormWord(query)
  let nextNorm  = nextChar(norm)
  let nextFnorm = nextChar(fnorm)

  var rows: seq[seq[cstring]] = @[]
  var seenIds: JsObject
  {.emit: [seenIds, " = new Set();"].}

  for row in getResultRows(dbQuery2("""
      SELECT id, nilai, word, kind FROM entries
      WHERE nilai >= ? AND nilai < ? ORDER BY nilai LIMIT 21""",
      norm, nextNorm)):
    if row.len == 0: continue
    let rid = row[0]
    var seen: bool
    {.emit: [seen, " = ", seenIds, ".has(", rid, ");"].}
    if not seen:
      {.emit: [seenIds, ".add(", rid, ");"].}
      rows.add(row)

  for row in getResultRows(dbQuery2("""
      SELECT id, nilai, word, kind FROM entries
      WHERE nilai_norm >= ? AND nilai_norm < ? ORDER BY nilai LIMIT 21""",
      fnorm, nextFnorm)):
    if row.len == 0: continue
    let rid = row[0]
    var seen: bool
    {.emit: [seen, " = ", seenIds, ".has(", rid, ");"].}
    if not seen:
      {.emit: [seenIds, ".add(", rid, ");"].}
      rows.add(row)

  if rows.len == 0:
    return "<div class='not-found'><div class='nf-icon'>∅</div>" &
      "<p>Tidak ada kata dengan awalan <strong>&ldquo;" & htmlEsc(query) & "&rdquo;</strong>.</p></div>"
  if rows.len == 1:
    return "<div class='result-header'><span class='result-label'>Hasil untuk</span>" &
      "<h2 class='result-word'>" & htmlEsc(rows[0][2]) & "</h2></div>" & buildResultCards(rows)
  var listHtml: cstring = cstring(
    "<div class='result-header'><span class='result-label'>Ditemukan</span>" &
    "<h2 class='result-word'>" & $rows.len & " kata</h2></div><div class='word-list'>")
  for row in rows:
    listHtml = listHtml &
      "<button class='word-chip' onclick='nimSearchById(" & row[0] & ")'>" &
      htmlEsc(row[2]) & kindBadgeHtml(row[3]) & "</button>"
  return listHtml & "</div>"

proc searchFTS(query: cstring): cstring =
  let rows = getResultRows(dbQuery("""
    SELECT e.id, e.nilai, e.word, e.kind
    FROM entries_fts f
    JOIN entries e ON e.id = f.rowid
    WHERE entries_fts MATCH ?
    ORDER BY rank LIMIT 20""", query))
  if rows.len == 0:
    return "<div class='not-found'><div class='nf-icon'>∅</div>" &
      "<p>Tidak ada hasil FTS untuk <strong>&ldquo;" & htmlEsc(query) & "&rdquo;</strong>.</p></div>"
  return cstring("<div class='result-header'><span class='result-label'>FTS —</span>" &
    "<h2 class='result-word'>" & $rows.len & " hasil</h2></div>") & buildResultCards(rows)

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
    return "<div class='error'><div class='err-icon'>⏳</div><p>Database belum selesai dimuat.</p></div>"
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
    " ORDER BY e.nilai LIMIT 50"
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
    return "<div class='not-found'><div class='nf-icon'>∅</div>" &
      "<p>Tidak ada kata dengan " & htmlEsc(jenis) & " = <strong>" & htmlEsc(nilai) & "</strong>.</p></div>"

  let desc = katGet(jenis, nilai)
  let titleLabel: cstring = if desc != nilai: htmlEsc(nilai) & " — " & htmlEsc(desc) else: htmlEsc(nilai)

  var listHtml: cstring =
    "<div class='result-header'>" &
      "<span class='result-label'>" & htmlEsc(jenis) & "</span>" &
      "<h2 class='result-word'>" & titleLabel & "</h2>" &
    "</div>" &
    "<div class='word-list'>"
  for row in rows:
    listHtml = listHtml &
      "<button class='word-chip' onclick='nimSearchById(" & row[0] & ")'>" &
      htmlEsc(row[2]) & kindBadgeHtml(row[3]) & "</button>"
  listHtml = listHtml & "</div>"
  listHtml = listHtml &
    "<p style='margin-top:0.75rem;font-size:0.8rem;color:var(--text-muted)'>" &
    total & " kata ditemukan" &
    (if ($total != $rows.len): ", menampilkan " & cstring($rows.len) else: "") &
    "</p>"
  return listHtml

proc searchList(jenis: cstring): cstring =
  ## Mirrors --list: queries kategori_{jenis} joined with precomputed kategori_counts.
  if db.isNil:
    return "<div class='error'><div class='err-icon'>⏳</div><p>Database belum selesai dimuat.</p></div>"
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
    return "<div class='not-found'><div class='nf-icon'>∅</div>" &
      "<p>Tidak ada kategori untuk <strong>" & htmlEsc(jenis) & "</strong>.</p></div>"
 
  var html: cstring =
    "<div class='result-header'>" &
      "<span class='result-label'>Kategori</span>" &
      "<h2 class='result-word'>" & htmlEsc(jenis) & "</h2>" &
    "</div>" &
    "<div class='word-list'>"
  for row in rows:
    if row.len < 3: continue
    let nilai = row[0]
    let desc  = row[1]
    let cnt   = row[2]
    let onclick: cstring = "nimKat(\"" & jsStrEsc(jenis) & "\",\"" & jsStrEsc(nilai) & "\")"
    html = html &
      "<button class='word-chip' title='" & htmlEsc(desc) & "' onclick='" & onclick & "'>" &
      htmlEsc(nilai) &
      "<span style='margin-left:0.35rem;font-size:0.7rem;opacity:0.55'>(" & htmlEsc(cnt) & ")</span>" &
      "</button>"
  return html & "</div>"

proc getKatFilter(): cstring =
  let el = getById("kat-filter-input")
  if el.isNil: return ""
  return getValue(el)

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
    setText("result", "<div class='error'><div class='err-icon'>⏳</div><p>Database belum selesai dimuat.</p></div>")
    setClass("result", "hidden", false)
    return
  setLoading(false)
  let res = getById("result")
  if res.isNil: return
  updateHistory(query)
  var html: cstring
  case $mode
  of "fts":         html = searchFTS(query)
  of "prefix":      html = searchPrefix(query)
  of "kat-kelas":   html = searchKat("kelas",  getKatFilter(), query)
  of "kat-bahasa":  html = searchKat("bahasa", getKatFilter(), query)
  of "kat-bidang":  html = searchKat("bidang", getKatFilter(), query)
  of "kat-ragam":   html = searchKat("ragam",  getKatFilter(), query)
  of "list-kelas":  html = searchList("kelas")
  of "list-bahasa": html = searchList("bahasa")
  of "list-bidang": html = searchList("bidang")
  of "list-ragam":  html = searchList("ragam")
  else:
    html = searchExact(query)
    if ($html).contains("not-found"):
      let p = searchPrefix(query)
      if not ($p).contains("not-found"): html = p
  setInnerHTML(res, html)
  res.classList.remove("hidden")
  smoothScroll(res)

proc doSearch*() {.exportc.} =
  let mode = getMode()
  let inp = getById("search-input")
  if inp.isNil: return
  let v = getValue(inp)
  if v == "" and not ($mode).startsWith("list-"): return
  setLoading(true)
  doSearchWith(v, mode)

proc nimSearch*(word: cstring) {.exportc.} =
  let inp = getById("search-input")
  if not inp.isNil: setValue(inp, word)
  setLoading(true)
  doSearchWith(word, getMode())

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
  let inp = getById("search-input")
  if not inp.isNil: setValue(inp, nilai)
  let res = getById("result")
  if res.isNil: return
  if db.isNil:
    setText("result", "<div class='error'><div class='err-icon'>⏳</div><p>Database belum selesai dimuat.</p></div>")
    setClass("result", "hidden", false)
    return
  let html = searchKat(jenis, nilai, "")
  setInnerHTML(res, html)
  res.classList.remove("hidden")
  smoothScroll(res)

proc loadDatabase() {.async.} =
  setText("load-status", "Memulai sql.js…")
  setClass("load-overlay", "hidden", false)
  try:
    var sqlCfg: JsObject
    {.emit: [sqlCfg, " = {locateFile: function(f){return 'https://cdn.jsdelivr.net/npm/sql.js-fts5@1.4.0/dist/' + f;}}"].}
    let SQL = await initSqlJs(sqlCfg)
    setText("load-status", "Mengunduh kbbi.db…")
    var resp: JsObject
    {.emit: ["""
      try {
        const CACHE_NAME = '""", cacheKey, """';
        const URL = 'kbbi.db';

        const cache = await caches.open(CACHE_NAME);
        let response = await cache.match(URL);

        if (!response) {
          const fetched = await fetch(URL, { cache: 'no-store' });
          await cache.put(URL, fetched.clone());
          response = fetched;
        }

        """, resp, """ = response;
      } catch (e) {
        """, resp, """ = await fetch('kbbi.db');
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
    setText("load-status", "Gagal memuat database. Pastikan kbbi.db ada di folder yang sama dengan index.html.")

window.onload = proc(e: Event) =
  let inp    = getById("search-input")
  let btn    = getById("search-btn")
  let sel    = getById("search-mode")
  let katInp = getById("kat-filter-input")
  if not inp.isNil:
    addKbListener(inp, proc(ev: KeyboardEvent) =
      if ev.keyCode == 13: doSearch()
    )
  if not katInp.isNil:
    addKbListener(katInp, proc(ev: KeyboardEvent) =
      if ev.keyCode == 13: doSearch()
    )
  if not btn.isNil:
    addClickListener(btn, proc(ev: Event) = doSearch())
  if not sel.isNil:
    addChangeListener(sel, proc(ev: Event) = updateKatFilterRow(getMode()))
  discard loadDatabase()