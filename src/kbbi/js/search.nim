import std/[algorithm, jsffi, strutils]
import karax/[kbase, kdom, jjson]
import ./[config, ffi, db, render]

type SearchError* = enum
  SearchOk
  SearchDbNotReady
  SearchException
  SearchNotFound

type SearchResult* = object
  html*: kstring
  found*: bool
  word*: kstring
  error*: SearchError

proc buildResultHeader*(label: kstring, title: kstring): kstring =
  "<div class=\"result-header\"><span class=\"result-label\">" & label &
    "</span><h2 class=\"result-word\">" & htmlEsc(title) & "</h2></div>"

proc buildNotFoundHtml*(query: kstring, hint: kstring = ""): kstring =
  var html =
    "<div class=\"not-found\"><div class=\"nf-icon\">∅</div>" & "<p>" & hint &
    "</p></div>"
  return html

proc buildWordChip*(id: kstring, word: kstring, kind: kstring): kstring =
  "<button class=\"word-chip\" data-action=\"search-id\" data-id=\"" & id &
    "\" role=\"listitem\" aria-label=\"" & htmlEsc(word) & "\">" & htmlEsc(word) &
    kindBadgeHtml(kind) & "</button>"

proc buildWordList*(rows: seq[seq[kstring]]): kstring =
  var listHtml: kstring = "<div class=\"word-list\" role=\"list\">"
  let sorted = rows.sortedByIt(
    if it.len >= 3:
      it[2].len
    else:
      0
  )
  for row in sorted:
    if row.len >= 3:
      listHtml =
        listHtml &
        buildWordChip(
          row[0],
          row[2],
          if row.len > 3:
            row[3]
          else:
            "",
        )
  return listHtml & "</div>"

proc setLoading*(on: bool) =
  let el = document.getElementById("search-btn")
  if not el.isNil:
    if on:
      el.classList.add("loading")
    else:
      el.classList.remove("loading")
  let spinner = document.getElementById("spinner")
  if not spinner.isNil:
    if on:
      spinner.classList.remove("hidden")
    else:
      spinner.classList.add("hidden")
  let lbl: kstring = if on: "Mencari..." else: "Cari"
  let btnText = document.getElementById("btn-text")
  if not btnText.isNil:
    btnText.innerHTML = lbl

proc searchById*(id: kstring): SearchResult =
  let rows = getResultRows(
    dbQuery(
      """
    SELECT id, nilai, word, kind FROM entries WHERE id=?""", id,
    )
  )
  if rows.len == 0:
    return SearchResult(
      html: buildNotFoundHtml("", "Entri tidak ditemukan."),
      found: false,
      word: "",
      error: SearchNotFound,
    )
  let word = rows[0][2]
  let nilai = rows[0][1]
  let titleClean = word.removeNumberTag()
  let html = buildResultHeader("Hasil untuk", titleClean) & buildResultCards(rows)
  return SearchResult(html: html, found: true, word: nilai, error: SearchOk)

proc searchExact*(query: kstring): SearchResult =
  let norm = normalizeWord(query)
  let fnorm = fuzzyNormWord(query)
  var rows = getResultRows(
    dbQuery(
      """
    SELECT id, nilai, word, kind FROM entries WHERE nilai=?""", norm,
    )
  )
  if rows.len == 0 and fnorm != norm:
    rows = getResultRows(
      dbQuery(
        """
      SELECT id, nilai, word, kind FROM entries WHERE nilai_norm=?""", fnorm,
      )
    )
  if rows.len == 0:
    let notFoundMsg =
      "<p>Kata <strong>&ldquo;" & htmlEsc(query) &
      "&rdquo;</strong> tidak ditemukan dalam KBBI.</p>" &
      "<p class=\"nf-hint\">Coba mode <em>Awalan</em> atau <em>Teks penuh</em>.</p>"
    return SearchResult(
      html: buildNotFoundHtml("", notFoundMsg),
      found: false,
      word: "",
      error: SearchNotFound,
    )
  let titleClean = rows[0][2].removeNumberTag()
  let html = buildResultHeader("Hasil untuk", titleClean) & buildResultCards(rows)
  return SearchResult(html: html, found: true, word: rows[0][2], error: SearchOk)

proc searchPrefix*(query: kstring): SearchResult =
  let norm = normalizeWord(query)
  let fnorm = fuzzyNormWord(query)
  let nextNorm = nextChar(norm)
  let nextFnorm = nextChar(fnorm)

  var rows: seq[seq[kstring]] = @[]
  var seenIds: seq[kstring] = @[]

  let pass1 = getResultRows(
    dbQuery(
      """
      SELECT id, nilai, word, kind FROM entries
      WHERE nilai >= ? AND nilai < ? ORDER BY nilai LIMIT """ &
        kstring($resultLimitPrefix),
      norm,
      nextNorm,
    )
  )
  for row in pass1:
    if row.len == 0:
      continue
    let rid = row[0]
    if not seenIds.contains(rid):
      seenIds.add(rid)
      rows.add(row)

  let pass2 = getResultRows(
    dbQuery(
      """
      SELECT id, nilai, word, kind FROM entries
      WHERE nilai_norm >= ? AND nilai_norm < ? ORDER BY nilai LIMIT """ &
        kstring($resultLimitPrefix),
      fnorm,
      nextFnorm,
    )
  )
  for row in pass2:
    if row.len == 0:
      continue
    let rid = row[0]
    if not seenIds.contains(rid):
      seenIds.add(rid)
      rows.add(row)

  if rows.len == 0:
    let notFoundMsg =
      "<p>Tidak ada kata dengan awalan <strong>&ldquo;" & htmlEsc(query) &
      "&rdquo;</strong>.</p>"
    return SearchResult(
      html: buildNotFoundHtml("", notFoundMsg),
      found: false,
      word: "",
      error: SearchNotFound,
    )
  if rows.len == 1:
    let titleClean = rows[0][2].removeNumberTag()
    let html = buildResultHeader("Hasil untuk", titleClean) & buildResultCards(rows)
    return SearchResult(html: html, found: true, word: rows[0][2], error: SearchOk)
  var listHtml: kstring =
    kstring(
      "<div class=\"result-header\"><span class=\"result-label\">Ditemukan</span>" &
        "<h2 class=\"result-word\">" & $rows.len & " kata</h2></div>"
    ) & buildWordList(rows)
  return SearchResult(html: listHtml, found: true, word: "", error: SearchOk)

proc searchFTS*(query: kstring): SearchResult =
  var safeQuery: kstring
  {.
    emit: """
    `safeQuery` = '"' + String(`query`).replace(/"/g, '""') + '"';
  """
  .}
  let ftsSql: kstring =
    "SELECT e.id, e.nilai, e.word, e.kind FROM entries_fts f " &
    "JOIN entries e ON e.id = f.rowid WHERE entries_fts MATCH ? ORDER BY rank LIMIT " &
    kstring($resultLimitFts)
  var ftsErr: kstring = ""
  var res: JsonNode
  try:
    res = dbQuery(ftsSql, safeQuery)
  except:
    ftsErr = "Kueri FTS tidak valid"
  if ftsErr != "" or res.isNil:
    let errMsg = "<p>Kueri FTS tidak valid: <em>" & htmlEsc(safeQuery) & "</em></p>"
    return SearchResult(
      html: buildNotFoundHtml("", errMsg),
      found: false,
      word: "",
      error: SearchException,
    )
  let rows = getResultRows(res)
  if rows.len == 0:
    let notFoundMsg =
      "<p>Tidak ada hasil FTS untuk <strong>&ldquo;" & htmlEsc(query) &
      "&rdquo;</strong>.</p>"
    return SearchResult(
      html: buildNotFoundHtml("", notFoundMsg),
      found: false,
      word: "",
      error: SearchNotFound,
    )
  let html =
    buildResultHeader("FTS —", kstring($rows.len & " hasil")) & buildResultCards(rows)
  return SearchResult(html: html, found: true, word: "", error: SearchOk)

proc katColName*(jenis: kstring): kstring =
  case $jenis
  of "kelas":
    return "pos"
  of "bahasa":
    return "bahasa"
  of "bidang":
    return "bidang"
  of "ragam":
    return "ragam"
  of "jenis":
    return "markers"
  else:
    return jenis

proc searchKat*(jenis, nilai, query: kstring): SearchResult =
  if sqlDb.isNil:
    return SearchResult(
      html: dbLoadingError, found: false, word: "", error: SearchDbNotReady
    )
  let col = katColName(jenis)
  let norm = normalizeWord(query)
  let fnorm = fuzzyNormWord(query)
  let nextNorm = nextChar(norm)
  let nextFnorm = nextChar(fnorm)
  let hasQuery = $query != ""
  let katClause: kstring = "(',' || s." & col & " || ',') LIKE '%,' || ? || ',%'"
  let wordClause: kstring =
    if hasQuery:
      " AND (e.nilai >= ? AND e.nilai < ? OR e.nilai_norm >= ? AND e.nilai_norm < ?)"
    else:
      ""
  let likeQ: kstring =
    "SELECT DISTINCT e.id, e.nilai, e.word, e.kind FROM entries e " &
    "JOIN senses s ON e.id = s.entry_id " & "WHERE " & katClause & wordClause &
    " ORDER BY e.nilai LIMIT " & kstring($resultLimitKat)
  let countQ: kstring =
    "SELECT COUNT(DISTINCT e.id) FROM entries e " & "JOIN senses s ON e.id = s.entry_id " &
    "WHERE " & katClause & wordClause
  let res =
    if hasQuery:
      dbQuery(likeQ, nilai, norm, nextNorm, fnorm, nextFnorm)
    else:
      dbQuery(likeQ, nilai)
  let rows = getResultRows(res)
  let countRes =
    if hasQuery:
      dbQuery(countQ, nilai, norm, nextNorm, fnorm, nextFnorm)
    else:
      dbQuery(countQ, nilai)
  var total: kstring = "0"
  let countRows = getResultRows(countRes)
  if countRows.len > 0 and countRows[0].len > 0:
    total = countRows[0][0]

  if rows.len == 0:
    let notFoundMsg =
      "<p>Tidak ada kata dengan " & htmlEsc(jenis) & " = <strong>" & htmlEsc(nilai) &
      "</strong>.</p>"
    return SearchResult(
      html: buildNotFoundHtml("", notFoundMsg),
      found: false,
      word: "",
      error: SearchNotFound,
    )

  let desc = katGet(jenis, nilai)
  let titleLabel: kstring =
    if desc != nilai:
      htmlEsc(nilai) & " — " & htmlEsc(desc)
    else:
      htmlEsc(nilai)

  var listHtml: kstring =
    "<div class=\"result-header\">" & "<span class=\"result-label\">" & htmlEsc(jenis) &
    "</span>" & "<h2 class=\"result-word\">" & titleLabel.removeNumberTag() & "</h2>" &
    "</div>" & buildWordList(rows) &
    "<p style='margin-top:0.75rem;font-size:0.8rem;color:var(--text-muted)'>" & total &
    " kata ditemukan" &
    (if ($total).parseInt != rows.len: ", menampilkan " & kstring($rows.len)
    else: "") & "</p>"
  return SearchResult(html: listHtml, found: true, word: "", error: SearchOk)

proc searchList*(jenis: kstring): SearchResult =
  if sqlDb.isNil:
    return SearchResult(
      html: dbLoadingError, found: false, word: "", error: SearchDbNotReady
    )
  let tableName: kstring = "kategori_" & jenis
  let listQ: kstring =
    "SELECT k.nilai, k.desc, COALESCE(c.cnt, 0) AS cnt " & "FROM " & tableName & " k " &
    "LEFT JOIN kategori_counts c ON c.jenis = '" & jenis & "' AND c.nilai = k.nilai " &
    "ORDER BY cnt DESC"
  let rows = getResultRows(dbQuery(listQ))
  if rows.len == 0:
    let notFoundMsg =
      "<p>Tidak ada kategori untuk <strong>" & htmlEsc(jenis) & "</strong>.</p>"
    return SearchResult(
      html: buildNotFoundHtml("", notFoundMsg),
      found: false,
      word: "",
      error: SearchNotFound,
    )

  var html: kstring =
    "<div class=\"result-header\">" & "<span class=\"result-label\">Kategori</span>" &
    "<h2 class=\"result-word\">" & htmlEsc(jenis.removeNumberTag()) & "</h2>" & "</div>" &
    "<div class=\"word-list\" role=\"list\">"
  for row in rows:
    if row.len < 3:
      continue
    let nilai = row[0]
    let desc = row[1]
    let cnt = row[2]
    html =
      html & "<button class=\"word-chip\" data-action=\"filter-kat\" data-jenis=\"" &
      htmlEsc(jenis) & "\" data-nilai=\"" & htmlEsc(nilai) & "\"" & " title=\"" &
      htmlEsc(desc) & "\" role=\"listitem\" aria-label=\"" & htmlEsc(nilai) & ": " &
      htmlEsc(cnt) & " kata\">" & htmlEsc(nilai) & "<span class=\"kat-count\">(" &
      htmlEsc(cnt) & ")</span>" & "</button>"
  return SearchResult(html: html & "</div>", found: true, word: "", error: SearchOk)
