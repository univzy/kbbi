import std/[jsffi, strutils]
import ./[ffi, db, utils]

proc badgeWithTooltip*(cls, code, jenis: cstring): cstring =
  let desc = katGet(jenis, code)
  let title: cstring = if desc != code: " title=\"" & htmlEsc(desc) & "\"" else: ""
  return "<span class=\"badge " & cls & "\"" & title & ">" & htmlEsc(code) & "</span>"

proc kindBadgeHtml*(kind: cstring): cstring =
  case $kind
  of "foreign":     return "<span class=\"kind-badge foreign\" title=\"Kata/ungkapan asing\">asing</span>"
  of "phrase":      return "<span class=\"kind-badge phrase\" title=\"Frasa\">frasa</span>"
  of "nonstandard": return "<span class=\"kind-badge nonstandard\" title=\"Ejaan tidak baku\">tidak baku</span>"
  of "alias":       return "<span class=\"kind-badge alias\" title=\"Alias\">alias</span>"
  of "redirect":    return "<span class=\"kind-badge redirect\" title=\"Merujuk ke entri lain\">lihat</span>"
  of "group":       return "<span class=\"kind-badge group\" title=\"Beberapa entri berbagi satu kunci\">grup</span>"
  else:             return ""

proc markerBadge*(m: cstring): cstring =
  case $m
  of "ki":   return "<span class=\"badge marker\" title=\"Kiasan (figuratif/idiom)\">ki</span>"
  of "sing": return "<span class=\"badge marker\" title=\"Singkatan\">sing</span>"
  of "akr":  return "<span class=\"badge marker\" title=\"Akronim\">akr</span>"
  of "ukp":  return "<span class=\"badge marker\" title=\"Ungkapan (ekspresi asing)\">ukp</span>"
  else:      return "<span class=\"badge marker\">" & htmlEsc(m) & "</span>"

proc renderMarkerBadges*(m: cstring): cstring =
  if not isValidString(m): return ""
  var badges: cstring = ""
  let ms = ($m).split(",")
  for mk in ms:
    let mkc = mk.strip()
    if mkc != "": badges = badges & markerBadge(cstring(mkc))
  return badges

proc xrefGroupLabel*(kind: cstring): cstring =
  case $kind
  of "baku":       return "<span class=\"xref-kind baku\" title=\"Bentuk baku\">bentuk baku</span>"
  of "dasar":      return "<span class=\"xref-kind dasar\" title=\"Kata dasar\">kata dasar</span>"
  of "lihat":      return "<span class=\"xref-kind lihat\" title=\"Lihat juga\">lihat juga</span>"
  of "turunan":    return "<span class=\"xref-kind turunan\" title=\"Kata turunan\">kata turunan</span>"
  of "gabungan":   return "<span class=\"xref-kind gabungan\" title=\"Kata gabungan\">kata gabungan</span>"
  of "peribahasa": return "<span class=\"xref-kind peribahasa\" title=\"Peribahasa\">peribahasa</span>"
  else:            return "<span class=\"xref-kind tidak-baku\" title=\"Bentuk tidak baku\">bentuk tidak baku</span>"

proc buildXrefLinks*(xrArr: JsObject): seq[cstring] =
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

proc renderXrefs*(xrArr: JsObject): cstring =
  let links = buildXrefLinks(xrArr)
  if links.len == 0: return ""
  var html: cstring = "<div class=\"xrefs plain\">"
  for lk in links: html = html & lk
  return html & "</div>"

proc renderXrefsWithLabel*(xrArr: JsObject, label: cstring): cstring =
  let links = buildXrefLinks(xrArr)
  if links.len == 0: return ""
  var html: cstring = "<div class=\"xref-group\">" & xrefGroupLabel(label)
  for lk in links: html = html & lk
  return html & "</div>"

proc renderXrefGroups*(xgArr: JsObject): cstring =
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

proc renderSense*(s: JsObject, headword: cstring,
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

proc renderRedirectCard*(word, kind, entryId: cstring): cstring =
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

proc renderEntry*(word, kind, entryId, sensesJson: cstring): cstring =
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

proc buildResultCards*(rows: seq[seq[cstring]]): cstring =
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