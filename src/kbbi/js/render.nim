import std/[jsffi, strutils]
import karax/[kbase, jjson]
import ./[ffi, db, utils]

proc safeStr(node: JsonNode): kstring {.importcpp: "String(#||'')".}
proc safeInt(node: JsonNode): int {.importcpp: "(#|0)".}

proc badgeWithTooltip*(cls, code, jenis: kstring): kstring =
  let desc = katGet(jenis, code)
  let title: kstring =
    if desc != code:
      " title=\"" & htmlEsc(desc) & "\""
    else:
      ""
  return "<span class=\"badge " & cls & "\"" & title & ">" & htmlEsc(code) & "</span>"

proc kindBadgeHtml*(kind: kstring): kstring =
  case $kind
  of "foreign":
    return
      "<span class=\"kind-badge foreign\" title=\"Kata/ungkapan asing\">asing</span>"
  of "phrase":
    return "<span class=\"kind-badge phrase\" title=\"Frasa\">frasa</span>"
  of "nonstandard":
    return
      "<span class=\"kind-badge nonstandard\" title=\"Ejaan tidak baku\">tidak baku</span>"
  of "alias":
    return "<span class=\"kind-badge alias\" title=\"Alias\">alias</span>"
  of "redirect":
    return
      "<span class=\"kind-badge redirect\" title=\"Merujuk ke entri lain\">lihat</span>"
  of "group":
    return
      "<span class=\"kind-badge group\" title=\"Beberapa entri berbagi satu kunci\">grup</span>"
  else:
    return ""

proc markerBadge*(m: kstring): kstring =
  case $m
  of "ki":
    return "<span class=\"badge marker\" title=\"Kiasan (figuratif/idiom)\">ki</span>"
  of "sing":
    return "<span class=\"badge marker\" title=\"Singkatan\">sing</span>"
  of "akr":
    return "<span class=\"badge marker\" title=\"Akronim\">akr</span>"
  of "ukp":
    return "<span class=\"badge marker\" title=\"Ungkapan (ekspresi asing)\">ukp</span>"
  else:
    return "<span class=\"badge marker\">" & htmlEsc(m) & "</span>"

proc renderMarkerBadges*(m: kstring): kstring =
  if not isValidString(m):
    return ""
  var badges: kstring = ""
  let ms = ($m).split(",")
  for mk in ms:
    let mkc = mk.strip()
    if mkc != "":
      badges = badges & markerBadge(kstring(mkc))
  return badges

proc xrefGroupLabel*(kind: kstring): kstring =
  case $kind
  of "baku":
    return "<span class=\"xref-kind baku\" title=\"Bentuk baku\">bentuk baku</span>"
  of "dasar":
    return "<span class=\"xref-kind dasar\" title=\"Kata dasar\">kata dasar</span>"
  of "lihat":
    return "<span class=\"xref-kind lihat\" title=\"Lihat juga\">lihat juga</span>"
  of "turunan":
    return
      "<span class=\"xref-kind turunan\" title=\"Kata turunan\">kata turunan</span>"
  of "gabungan":
    return
      "<span class=\"xref-kind gabungan\" title=\"Kata gabungan\">kata gabungan</span>"
  of "peribahasa":
    return "<span class=\"xref-kind peribahasa\" title=\"Peribahasa\">peribahasa</span>"
  else:
    return
      "<span class=\"xref-kind tidak-baku\" title=\"Bentuk tidak baku\">bentuk tidak baku</span>"

proc buildXrefLinks*(xrArr: JsonNode): seq[kstring] =
  var links: seq[kstring] = @[]
  if xrArr.isNil or xrArr.len == 0:
    return links
  for item in xrArr:
    let id = safeInt(item)
    if id == 0:
      continue
    let w = lookupWordById(id)
    if isValidString(w):
      links.add(buildDataButton(w, "search-id", kstring($id), w))
    else:
      links.add("<span class=\"xref-id\">#" & kstring($id) & "</span>")
  return links

proc renderXrefsWithLabel*(xrArr: JsonNode, label: kstring): kstring =
  let links = buildXrefLinks(xrArr)
  if links.len == 0:
    return ""
  var html: kstring = "<div class=\"xref-group\">" & xrefGroupLabel(label)
  for lk in links:
    html = html & lk
  return html & "</div>"

proc renderXrefs*(xrArr: JsonNode): kstring =
  return renderXrefsWithLabel(xrArr, "lihat")

proc renderXrefGroups*(xgArr: JsonNode): kstring =
  if xgArr.isNil or xgArr.len == 0:
    return ""
  var html: kstring = ""
  for grp in xgArr:
    let kind = safeStr(grp["kind"])
    let refs = grp["refs"]
    let links = buildXrefLinks(refs)
    if links.len == 0:
      continue
    html = html & "<div class=\"xref-group\">" & xrefGroupLabel(kind)
    for lk in links:
      html = html & lk
    html = html & "</div>"
  return html

proc renderSense*(
    s: JsonNode, headword: kstring, suppressXrefGroups = false, xrefsLabel: kstring = ""
): kstring =
  let num = safeStr(s["number"])
  let p = safeStr(s["pos"])
  let bh = safeStr(s["bahasa"])
  let bd = safeStr(s["bidang"])
  let r = safeStr(s["ragam"])
  let m = safeStr(s["markers"])
  let t = safeStr(s["text"])
  let at = safeStr(s["alt_text"])
  let l = safeStr(s["latin"])
  let ab = safeStr(s["abbrev"])
  let lk = safeStr(s["link"])
  let ch = safeStr(s["chem"])

  var numHtml: kstring = ""
  if isValidString(num):
    numHtml = "<span class=\"sense-num\">" & htmlEsc(num) & "</span>"

  var badges: kstring = ""
  if isValidString(p):
    badges = badges & badgeWithTooltip("kelas", p, "kelas")
  if isValidString(bh):
    badges = badges & badgeWithTooltip("bahasa", bh, "bahasa")
  if isValidString(bd):
    let bdDesc = katGet("bidang", bd)
    let bdTitle: kstring =
      if bdDesc != bd:
        " title=\"" & htmlEsc(bdDesc) & "\""
      else:
        ""
    badges =
      badges & "<span class=\"badge bidang\"" & bdTitle & ">[" & htmlEsc(bd) & "]</span>"
  if isValidString(r):
    badges = badges & badgeWithTooltip("ragam", r, "ragam")
  badges = badges & renderMarkerBadges(m)

  var body: kstring = ""
  if isValidString(t):
    body = body & "<span class=\"def-text\">" & htmlEsc(t) & "</span>"
  if isValidString(ab):
    body =
      body & " <span class=\"def-abbrev\" title=\"Kepanjangan singkatan\">(" &
      htmlEsc(ab) & ")</span>"
  if isValidString(at):
    body =
      body & " <span class=\"def-note\">lihat: " & buildDataButton(at, "search", at, at) &
      "</span>"
  if isValidString(lk):
    body =
      body & " <span class=\"def-note\">= " & buildDataButton(lk, "search", lk, lk) &
      "</span>"
  if isValidString(l):
    body = body & " <span class=\"def-latin\"><em>" & htmlEsc(l) & "</em></span>"
  if isValidString(ch):
    body = body & " <span class=\"def-chem\">" & htmlEsc(ch) & "</span>"

  var exHtml: kstring = ""
  let exArr = s["examples"]
  if not exArr.isNil and exArr.len > 0:
    exHtml = "<ul class=\"examples\" role=\"list\">"
    for ex in exArr:
      let raw = safeStr(ex)
      exHtml =
        exHtml & "<li role=\"listitem\">" & htmlEsc(replaceHeadword(raw, headword)) &
        "</li>"
    exHtml = exHtml & "</ul>"

  let xrHtml =
    if xrefsLabel != "":
      renderXrefsWithLabel(s["xrefs"], xrefsLabel)
    else:
      renderXrefs(s["xrefs"])
  let xgHtml: kstring =
    if suppressXrefGroups:
      ""
    else:
      renderXrefGroups(s["xref_groups"])

  return
    "<li class=\"sense-item\">" & numHtml & "<div class=\"sense-right\">" &
    "<div class=\"sense-meta\">" & badges & "</div>" & "<div class=\"sense-body\">" &
    body & exHtml & xrHtml & xgHtml & "</div>" & "</div></li>"

proc renderRedirectCard*(word, kind, entryId: kstring): kstring =
  var targets: kstring = ""
  let atRows = getResultRows(
    dbQuery(
      "SELECT altText FROM senses WHERE entry_id=? AND altText != '' LIMIT 1", entryId
    )
  )
  if atRows.len > 0 and atRows[0].len > 0 and isValidString(atRows[0][0]):
    let at = atRows[0][0]
    targets =
      "<button class=\"xref-link prominent\" data-action=\"search\" data-query=\"" &
      htmlEsc(at) & "\" aria-label=\"Cari: " & htmlEsc(at) & "\">" & htmlEsc(at) &
      " →</button>"
  else:
    let xrRows = getResultRows(
      dbQuery(
        "SELECT sx.xref_id FROM senses s JOIN sense_xrefs sx ON sx.sense_id = s.id WHERE s.entry_id=? LIMIT 5",
        entryId,
      )
    )
    if xrRows.len > 0:
      var links: kstring = ""
      for row in xrRows:
        if row.len == 0:
          continue
        let id = row[0]
        let w = lookupWordById(($id).parseInt)
        if isValidString(w):
          links = links & buildDataButton(w, "search-id", id, w)
      if links != "":
        targets = "<div class=\"xref-plain\">" & links & "</div>"
    if targets == "":
      let xgRows = getResultRows(
        dbQuery(
          "SELECT sxg.ref_id FROM senses s JOIN sense_xref_groups sxg ON sxg.sense_id = s.id WHERE s.entry_id=? AND sxg.kind='baku' LIMIT 5",
          entryId,
        )
      )
      if xgRows.len > 0:
        var links: kstring = ""
        for row in xgRows:
          if row.len == 0:
            continue
          let id = row[0]
          let w = lookupWordById(($id).parseInt)
          if isValidString(w):
            links = links & buildDataButton(w, "search-id", id, w)
        if links != "":
          targets = "<div class=\"xref-group\">" & links & "</div>"
    if targets == "":
      let revRows = getResultRows(
        dbQuery(
          "SELECT DISTINCT e.id, e.word FROM sense_xref_groups sxg JOIN senses s ON s.id = sxg.sense_id JOIN entries e ON e.id = s.entry_id WHERE sxg.ref_id=? AND sxg.kind='baku' LIMIT 5",
          entryId,
        )
      )
      if revRows.len > 0:
        var links: kstring = ""
        for row in revRows:
          if row.len < 2:
            continue
          let id = row[0]
          let w = row[1]
          if isValidString(w):
            links = links & buildDataButton(w, "search-id", id, w)
        if links != "":
          targets = "<div class=\"xref-plain\">" & links & "</div>"

  let lbl: kstring =
    case $kind
    of "alias": "merupakan alias dari"
    of "redirect": "merujuk ke"
    else: "varian dari"
  return
    "<div class=\"redirect-card\">" & "<span class=\"redirect-icon\">↪</span>" &
    "<div class=\"redirect-body\">" & "<span class=\"redirect-word\">" & htmlEsc(word) &
    "</span>" & "<span class=\"redirect-label\"> " & lbl & " </span>" & targets &
    "</div></div>"

proc renderEntry*(word, kind, entryId, sensesJson: kstring): kstring =
  let kindStr = $kind
  if kindStr == "redirect" or kindStr == "alias":
    return renderRedirectCard(word, kind, entryId)
  if sensesJson == "" or sensesJson == "[]":
    return ""

  let node = parse(sensesJson)
  if node.isNil or node.len == 0:
    return ""

  var html: kstring = ""
  if node.hasField("group"):
    let variants = node["variants"]
    if variants.isNil:
      return ""
    let variantCount = variants.len
    for i in 0 ..< variantCount:
      let v = variants[i]
      let vw = safeStr(v["word"])
      let vk = safeStr(v["kind"])
      let ss = v["senses"]
      let displayWord = if isValidString(vw): vw else: word
      let showBadge = not (variantCount == 1 and $vk == "nonstandard")
      html =
        html & "<div class=\"variant\">" & "<div class=\"variant-head\"><em>" &
        htmlEsc(displayWord) & "</em>" & (if showBadge: kindBadgeHtml(vk)
        else: "") & "</div>" & "<ol class=\"sense-list\">"
      if not ss.isNil:
        let isNonstandard = $vk == "nonstandard"
        for j in 0 ..< ss.len:
          html =
            html &
            renderSense(
              ss[j],
              displayWord,
              suppressXrefGroups = false,
              xrefsLabel =
                if isNonstandard:
                  kstring("tidak-baku")
                else:
                  "",
            )
      html = html & "</ol></div>"
  else:
    html = "<ol class=\"sense-list\">"
    for i in 0 ..< node.len:
      html = html & renderSense(node[i], word)
    html = html & "</ol>"

  return html

proc buildResultCards*(rows: seq[seq[kstring]]): kstring =
  var html: kstring = ""
  for row in rows:
    if row.len < 4:
      continue
    let id = row[0]
    let word = row[2]
    let kind = row[3]
    let sensesJson = fetchEntrySenses(id, word, kind)
    let syllable = fetchEntrySyllable(sensesJson)
    let syllableHtml: kstring =
      if isValidString(syllable):
        " <span class=\"entry-syllable\" title=\"Suku kata\">(" & htmlEsc(syllable) &
          ")</span>"
      else:
        ""
    html =
      html & "<article class=\"entry-card\" data-id=\"" & id & "\" role=\"article\">" &
      "<div class=\"entry-head\">" & "<span class=\"entry-lema\">" &
      htmlEsc(word.removeNumberTag()) & "</span>" & syllableHtml & kindBadgeHtml(kind) &
      "</div>" & renderEntry(word, kind, id, sensesJson) & "</article>"
  return html
