import std/[dom, jsffi, strutils]
import ./[config, ffi, db, render]

type SearchError* = enum
  SearchOk
  SearchDbNotReady
  SearchException
  SearchNotFound

type SearchResult* = object
  html*: cstring
  found*: bool
  word*: cstring
  error*: SearchError

proc buildResultHeader*(label: cstring, title: cstring): cstring =
  "<div class=\"result-header\"><span class=\"result-label\">" & label &
    "</span><h2 class=\"result-word\">" & htmlEsc(title) & "</h2></div>"

proc buildNotFoundHtml*(query: cstring, hint: cstring = ""): cstring =
  var html = "<div class=\"not-found\"><div class=\"nf-icon\">∅</div>" &
    "<p>" & hint & "</p></div>"
  return html

proc buildWordChip*(id: cstring, word: cstring, kind: cstring): cstring =
  "<button class=\"word-chip\" data-action=\"search-id\" data-id=\"" & id &
    "\" role=\"listitem\" aria-label=\"" & htmlEsc(word) & "\">" &
    htmlEsc(word) & kindBadgeHtml(kind) & "</button>"

proc buildWordList*(rows: seq[seq[cstring]]): cstring =
  var listHtml: cstring = "<div class=\"word-list\" role=\"list\">"
  for row in rows:
    if row.len >= 3:
      listHtml = listHtml & buildWordChip(row[0], row[2], if row.len > 3: row[3] else: "")
  return listHtml & "</div>"

proc setLoading*(on: bool) =
  let el = getById("search-btn")
  if not el.isNil:
    let elClassList = el.classList
    if on: elClassList.add("loading") else: elClassList.remove("loading")
  let spinner = getById("spinner")
  if not spinner.isNil:
    let spinnerClassList = spinner.classList
    if on: spinnerClassList.remove("hidden") else: spinnerClassList.add("hidden")
  let lbl: cstring = if on: "Mencari..." else: "Cari"
  let btnText = getById("btn-text")
  if not btnText.isNil: setInnerHTML(btnText, lbl)

proc searchById*(id: cstring): SearchResult =
  let rows = getResultRows(dbQuery("""
    SELECT id, nilai, word, kind FROM entries WHERE id=?""", id))
  if rows.len == 0:
    return SearchResult(
      html: buildNotFoundHtml("", "Entri tidak ditemukan."),
      found: false,
      word: "",
      error: SearchNotFound
    )
  let word = rows[0][2]
  let titleClean = word.removeNumberTag()
  let html = buildResultHeader("Hasil untuk", titleClean) & buildResultCards(rows)
  return SearchResult(
    html: html,
    found: true,
    word: word,
    error: SearchOk
  )

proc searchExact*(query: cstring): SearchResult =
  let norm  = normalizeWord(query)
  let fnorm = fuzzyNormWord(query)
  var rows = getResultRows(dbQuery("""
    SELECT id, nilai, word, kind FROM entries WHERE nilai=?""", norm))
  if rows.len == 0 and fnorm != norm:
    rows = getResultRows(dbQuery("""
      SELECT id, nilai, word, kind FROM entries WHERE nilai_norm=?""", fnorm))
  if rows.len == 0:
    let notFoundMsg = "<p>Kata <strong>&ldquo;" & htmlEsc(query) &
      "&rdquo;</strong> tidak ditemukan dalam KBBI.</p>" &
      "<p class=\"nf-hint\">Coba mode <em>Awalan</em> atau <em>Teks penuh</em>.</p>"
    return SearchResult(
      html: buildNotFoundHtml("", notFoundMsg),
      found: false,
      word: "",
      error: SearchNotFound
    )
  let titleClean = rows[0][2].removeNumberTag()
  let html = buildResultHeader("Hasil untuk", titleClean) & buildResultCards(rows)
  return SearchResult(
    html: html,
    found: true,
    word: rows[0][2],
    error: SearchOk
  )

proc searchPrefix*(query: cstring): SearchResult =
  let norm  = normalizeWord(query)
  let fnorm = fuzzyNormWord(query)
  let nextNorm  = nextChar(norm)
  let nextFnorm = nextChar(fnorm)

  var rows: seq[seq[cstring]] = @[]
  var seenIds: seq[cstring] = @[]

  let pass1 = getResultRows(dbQuery2("""
      SELECT id, nilai, word, kind FROM entries
      WHERE nilai >= ? AND nilai < ? ORDER BY nilai LIMIT """ & cstring($resultLimitPrefix),
      norm, nextNorm))
  for row in pass1:
    if row.len == 0: continue
    let rid = row[0]
    if not seenIds.contains(rid):
      seenIds.add(rid)
      rows.add(row)

  let pass2 = getResultRows(dbQuery2("""
      SELECT id, nilai, word, kind FROM entries
      WHERE nilai_norm >= ? AND nilai_norm < ? ORDER BY nilai LIMIT """ & cstring($resultLimitPrefix),
      fnorm, nextFnorm))
  for row in pass2:
    if row.len == 0: continue
    let rid = row[0]
    if not seenIds.contains(rid):
      seenIds.add(rid)
      rows.add(row)

  if rows.len == 0:
    let notFoundMsg = "<p>Tidak ada kata dengan awalan <strong>&ldquo;" & htmlEsc(query) & "&rdquo;</strong>.</p>"
    return SearchResult(
      html: buildNotFoundHtml("", notFoundMsg),
      found: false,
      word: "",
      error: SearchNotFound
    )
  if rows.len == 1:
    let titleClean = rows[0][2].removeNumberTag()
    let html = buildResultHeader("Hasil untuk", titleClean) & buildResultCards(rows)
    return SearchResult(
      html: html,
      found: true,
      word: rows[0][2],
      error: SearchOk
    )
  var listHtml: cstring =
    cstring("<div class=\"result-header\"><span class=\"result-label\">Ditemukan</span>" &
    "<h2 class=\"result-word\">" & $rows.len & " kata</h2></div>") &
    buildWordList(rows)
  return SearchResult(
    html: listHtml,
    found: true,
    word: "",
    error: SearchOk
  )

proc searchFTS*(query: cstring): SearchResult =
  var safeQuery: cstring
  {.emit: [safeQuery, " = '\"' + String(", query, ").replace(/\"/g, '\"\"') + '\"';"].}
  var res: JsObject
  var ftsErr: cstring = ""
  let ftsSql: cstring = "SELECT e.id, e.nilai, e.word, e.kind FROM entries_fts f " &
    "JOIN entries e ON e.id = f.rowid WHERE entries_fts MATCH ? ORDER BY rank LIMIT " & cstring($resultLimitFts)
  {.emit: ["""
    try {
      """, res, """ = """, sqlDb, """.exec(""", ftsSql, """, [""", safeQuery, """]);
    } catch(e) { """, ftsErr, """ = String(e.message || e); }
  """].}
  if $ftsErr != "":
    let errMsg = "<p>Kueri FTS tidak valid: <em>" & htmlEsc(ftsErr) & "</em></p>"
    return SearchResult(
      html: buildNotFoundHtml("", errMsg),
      found: false,
      word: "",
      error: SearchException
    )
  let rows = getResultRows(res)
  if rows.len == 0:
    let notFoundMsg = "<p>Tidak ada hasil FTS untuk <strong>&ldquo;" & htmlEsc(query) & "&rdquo;</strong>.</p>"
    return SearchResult(
      html: buildNotFoundHtml("", notFoundMsg),
      found: false,
      word: "",
      error: SearchNotFound
    )
  let html = buildResultHeader("FTS —", cstring($rows.len & " hasil")) & buildResultCards(rows)
  return SearchResult(
    html: html,
    found: true,
    word: "",
    error: SearchOk
  )

proc katColName*(jenis: cstring): cstring =
  case $jenis
  of "kelas":  return "pos"
  of "bahasa": return "bahasa"
  of "bidang": return "bidang"
  of "ragam":  return "ragam"
  of "jenis":  return "markers"
  else:        return jenis

proc searchKat*(jenis, nilai, query: cstring): SearchResult =
  if sqlDb.isNil:
    return SearchResult(
      html: dbLoadingError,
      found: false,
      word: "",
      error: SearchDbNotReady
    )
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
    " ORDER BY e.nilai LIMIT " & cstring($resultLimitKat)
  let countQ: cstring =
    "SELECT COUNT(DISTINCT e.id) FROM entries e " &
    "JOIN senses s ON e.id = s.entry_id " &
    "WHERE " & katClause & wordClause
  var res: JsObject
  if hasQuery:
    {.emit: [res, " = ", sqlDb, ".exec(", likeQ, ", [", nilai, ",", norm, ",", nextNorm, ",", fnorm, ",", nextFnorm, "]);"].}
  else:
    {.emit: [res, " = ", sqlDb, ".exec(", likeQ, ", [", nilai, "]);"].}
  let rows = getResultRows(res)
  var countRes: JsObject
  if hasQuery:
    {.emit: [countRes, " = ", sqlDb, ".exec(", countQ, ", [", nilai, ",", norm, ",", nextNorm, ",", fnorm, ",", nextFnorm, "]);"].}
  else:
    {.emit: [countRes, " = ", sqlDb, ".exec(", countQ, ", [", nilai, "]);"].}
  var total: cstring = "0"
  let countRows = getResultRows(countRes)
  if countRows.len > 0 and countRows[0].len > 0:
    total = countRows[0][0]

  if rows.len == 0:
    let notFoundMsg = "<p>Tidak ada kata dengan " & htmlEsc(jenis) & " = <strong>" & htmlEsc(nilai) & "</strong>.</p>"
    return SearchResult(
      html: buildNotFoundHtml("", notFoundMsg),
      found: false,
      word: "",
      error: SearchNotFound
    )

  let desc = katGet(jenis, nilai)
  let titleLabel: cstring = if desc != nilai: htmlEsc(nilai) & " — " & htmlEsc(desc) else: htmlEsc(nilai)

  var listHtml: cstring =
    "<div class=\"result-header\">" &
      "<span class=\"result-label\">" & htmlEsc(jenis) & "</span>" &
      "<h2 class=\"result-word\">" & titleLabel.removeNumberTag() & "</h2>" &
    "</div>" &
    buildWordList(rows) &
    "<p style='margin-top:0.75rem;font-size:0.8rem;color:var(--text-muted)'>" &
    total & " kata ditemukan" &
    (if ($total).parseInt != rows.len: ", menampilkan " & cstring($rows.len) else: "") &
    "</p>"
  return SearchResult(
    html: listHtml,
    found: true,
    word: "",
    error: SearchOk
  )

proc searchList*(jenis: cstring): SearchResult =
  if sqlDb.isNil:
    return SearchResult(
      html: dbLoadingError,
      found: false,
      word: "",
      error: SearchDbNotReady
    )
  let tableName: cstring = "kategori_" & jenis
  let listQ: cstring =
    "SELECT k.nilai, k.desc, COALESCE(c.cnt, 0) AS cnt " &
    "FROM " & tableName & " k " &
    "LEFT JOIN kategori_counts c ON c.jenis = '" & jenis & "' AND c.nilai = k.nilai " &
    "ORDER BY cnt DESC"
  var res: JsObject
  {.emit: [res, " = ", sqlDb, ".exec(", listQ, ");"].}
  let rows = getResultRows(res)
  if rows.len == 0:
    let notFoundMsg = "<p>Tidak ada kategori untuk <strong>" & htmlEsc(jenis) & "</strong>.</p>"
    return SearchResult(
      html: buildNotFoundHtml("", notFoundMsg),
      found: false,
      word: "",
      error: SearchNotFound
    )

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
  return SearchResult(
    html: html & "</div>",
    found: true,
    word: "",
    error: SearchOk
  )