import std/[os, strutils, tables, sequtils]
import pkg/[db_connector/db_sqlite]
import kbbi/common

const
  PREVIEW_LEN = 58
  RESULTS_LIMIT = 21
  DISPLAY_LIMIT = 20
  FTS_LIMIT = 20
  CATEGORY_LIMIT = 50

  VALID_COLUMNS = {
    "kelas": "pos",
    "bahasa": "bahasa",
    "bidang": "bidang",
    "ragam": "ragam",
    "jenis": "markers"
  }.toTable()

proc normalize(s: string): string =
  result = s.toLowerAscii()

proc printSense(sense: seq[string], examples: seq[string], xrefs: seq[string], indent = "  ") =
  if sense.len < 13: return
  
  var parts: seq[string]
  if sense[0].len > 0: parts.add(sense[0] & ".")
  if sense[1].len > 0: parts.add("(" & sense[1] & ")")
  if sense[2].len > 0: parts.add("(" & sense[2] & ")")
  if sense[3].len > 0: parts.add("[" & sense[3] & "]")
  if sense[4].len > 0: parts.add("(" & sense[4] & ")")
  if sense[5].len > 0:
    for m in sense[5].split(","): 
      if m.len > 0: parts.add(m)
  if sense[6].len > 0: parts.add(sense[6])
  if sense[7].len > 0: parts.add("(bentuk tidak baku: " & sense[7] & ")")
  if sense[8].len > 0: parts.add("(lihat: " & sense[8] & ")")
  if sense[9].len > 0: parts.add("; " & sense[9])
  if sense[11].len > 0: parts.add("= " & sense[11])
  if sense[12].len > 0: parts.add(sense[12])
  
  if parts.len > 0: echo indent & parts.join(" ")
  
  for ex in examples:
    echo indent & "  ~ " & ex
  
  if xrefs.len > 0:
    echo indent & "  -> " & xrefs.join(", ")

proc printEntry(db: DbConn, id: int, nilai, word, kind: string) =
  echo "[" & $id & "] " & word & "  (nilai: " & nilai & ")"

  var currentVariant = ""
  for row in db.fastRows(sql"""
    SELECT 
      s.id, s.entry_word, s.entry_kind,
      s.number, s.pos, s.bahasa, s.bidang, s.ragam, s.markers, s.text, 
      s.altForm, s.altText, s.latin, s.abbrev, s.link, s.chem
    FROM senses s
    WHERE s.entry_id = ? 
    ORDER BY s.id""", id):

    # print variant header when sub-entry changes (group entries only)
    if kind == "group" and row[1] != currentVariant:
      currentVariant = row[1]
      echo "  -- " & row[1] & " (" & row[2] & ")"

    var examples: seq[string]
    for exRow in db.fastRows(sql"""
      SELECT example FROM sense_examples WHERE sense_id = ? ORDER BY id""", row[0]):
      examples.add(exRow[0])

    var xrefs: seq[string]
    for xRow in db.fastRows(sql"""
      SELECT xref_id FROM sense_xrefs WHERE sense_id = ?""", row[0]):
      xrefs.add(xRow[0])

    let indent = if kind == "group": "     " else: "  "
    printSense(row[3..^1], examples, xrefs, indent)

proc printShort(pos, text, example: string, id, word: string) =
  var preview = ""
  preview = if pos.len > 0: "(" & pos & ") " & text else: text
  if example.len > 0: preview = preview & " - " & example
  
  if preview.len > PREVIEW_LEN: preview = preview[0 ..< PREVIEW_LEN] & "..."
  echo "  [" & align(id, 6) & "] " & alignLeft(word, 30) & " " & preview

proc printUsage() =
  echo "Usage:"
  echo "  kbbi_search_sqlite <kbbi.db> <query>"
  echo "  kbbi_search_sqlite <kbbi.db> --exact <word>"
  echo "  kbbi_search_sqlite <kbbi.db> --id <N>"
  echo "  kbbi_search_sqlite <kbbi.db> --kat kelas n"
  echo "  kbbi_search_sqlite <kbbi.db> --kat bahasa Jw"
  echo "  kbbi_search_sqlite <kbbi.db> --kat bidang Dok"
  echo "  kbbi_search_sqlite <kbbi.db> --kat ragam cak"
  echo "  kbbi_search_sqlite <kbbi.db> --fts <text>"
  echo "  kbbi_search_sqlite <kbbi.db> --list kelas"

proc main() =
  if paramCount() < 2: printUsage(); quit(1)

  let dbPath = paramStr(1)
  if not fileExists(dbPath):
    echo "Not found: ", dbPath
    quit(1)

  let db = open(dbPath, "", "", "")
  defer: db.close()
  db.exec(sql"PRAGMA query_only = ON")
  db.exec(sql"PRAGMA cache_size = -32000")

  let cmd = paramStr(2)

  case cmd

  of "--id":
    if paramCount() < 3: printUsage(); quit(1)
    let row = db.getRow(sql"""
      SELECT id, nilai, word, kind FROM entries WHERE id = ?""", paramStr(3))
    if row[0] == "": echo "Not found"
    else: printEntry(db, parseInt(row[0]), row[1], row[2], row[3])

  of "--exact":
    if paramCount() < 3: printUsage(); quit(1)
    let norm  = normalize(paramStr(3))
    let fnorm = fuzzyNorm(paramStr(3))
    var row = db.getRow(sql"""
      SELECT id, nilai, word, kind FROM entries WHERE nilai = ?""", norm)
    if row[0] == "":
      row = db.getRow(sql"""
        SELECT id, nilai, word, kind FROM entries WHERE nilai_norm = ?""", fnorm)
    if row[0] == "": echo "'" & paramStr(3) & "' not found"
    else: printEntry(db, parseInt(row[0]), row[1], row[2], row[3])

  of "--kat":
    if paramCount() < 4: printUsage(); quit(1)
    let jenis = paramStr(3)
    let nilai = paramStr(4)
    
    if jenis notin VALID_COLUMNS:
      echo "Invalid category: " & jenis
      echo "Valid categories: " & VALID_COLUMNS.keys.toSeq().join(", ")
      quit(1)
    
    let col = VALID_COLUMNS[jenis]

    var count = 0
    let likeClause = "(',' || " & col & " || ',') LIKE '%,' || ? || ',%'"
    
    for row in db.fastRows(sql("""
      SELECT DISTINCT e.id, e.word, COALESCE(s.pos, ''), COALESCE(s.text, ''), COALESCE(se.example, '')
      FROM entries e
      JOIN senses s ON e.id = s.entry_id
      LEFT JOIN (SELECT sense_id, MIN(id) as exid FROM sense_examples GROUP BY sense_id) se1 ON s.id = se1.sense_id
      LEFT JOIN sense_examples se ON se.id = se1.exid
      WHERE """ & likeClause & " ORDER BY e.nilai LIMIT " & $CATEGORY_LIMIT), nilai):
      printShort(row[2], row[3], row[4], row[0], row[1])
      count += 1
    
    let total = db.getValue(
      sql("SELECT COUNT(DISTINCT e.id) FROM entries e " &
          "JOIN senses s ON e.id = s.entry_id " &
          "WHERE " & likeClause), nilai)
    echo "\n" & total & " total for " & jenis & "=" & nilai &
         " (showing " & $count & ")"

  of "--fts":
    if paramCount() < 3: printUsage(); quit(1)
    let query = paramStr(3)
    var count = 0
    var matchIds: seq[string]
    for row in db.fastRows(sql("""
      SELECT e.id FROM entries_fts f
      JOIN entries e ON e.id = f.rowid
      WHERE entries_fts MATCH ?
      ORDER BY rank 
      LIMIT """ & $FTS_LIMIT), query):
      matchIds.add(row[0])

    if matchIds.len > 0:
      let idList = matchIds.join(",")
      for row in db.fastRows(sql("""
        SELECT e.id, e.word, COALESCE(s.pos, ''), COALESCE(s.text, ''), COALESCE(se.example, '')
        FROM entries e
        LEFT JOIN (SELECT entry_id, MIN(id) as sid FROM senses GROUP BY entry_id) s1 ON e.id = s1.entry_id
        LEFT JOIN senses s ON s.id = s1.sid
        LEFT JOIN (SELECT sense_id, MIN(id) as exid FROM sense_examples GROUP BY sense_id) se1 ON s.id = se1.sense_id
        LEFT JOIN sense_examples se ON se.id = se1.exid
        WHERE e.id IN (""" & idList & ")")):
        printShort(row[2], row[3], row[4], row[0], row[1])
        inc count
    echo "\n" & $count & " FTS results for '" & query & "'"

  of "--list":
    if paramCount() < 3: printUsage(); quit(1)
    let jenis = paramStr(3)
    
    if jenis notin VALID_COLUMNS:
      echo "Invalid category: " & jenis
      quit(1)
     
    echo "Categories for " & jenis & ":"
    let tableName = "kategori_" & jenis
    let listQ = sql(
      "SELECT k.nilai, k.desc, COALESCE(c.cnt, 0) as cnt " &
      "FROM " & tableName & " k " &
      "LEFT JOIN kategori_counts c ON c.jenis = '" & jenis & "' AND c.nilai = k.nilai " &
      "ORDER BY cnt DESC")
    for row in db.fastRows(listQ):
      echo "  " & alignLeft(row[0], 30) & " " &
           alignLeft(row[1], 40) & " (" & row[2] & ")"

  else:
    let norm  = normalize(cmd)
    let fnorm = fuzzyNorm(cmd)
    var nextNorm  = norm;  if nextNorm.len  > 0: nextNorm[^1]  = char(ord(nextNorm[^1])  + 1)
    var nextFnorm = fnorm; if nextFnorm.len > 0: nextFnorm[^1] = char(ord(nextFnorm[^1]) + 1)

    var seen: seq[string]
    var rows: seq[string]

    for row in db.fastRows(sql("""
      SELECT id FROM entries WHERE nilai >= ? AND nilai < ?
      ORDER BY nilai LIMIT """ & $RESULTS_LIMIT), norm, nextNorm):
      if row[0] notin seen:
        seen.add(row[0])
        rows.add(row[0])

    for row in db.fastRows(sql("""
      SELECT id FROM entries WHERE nilai_norm >= ? AND nilai_norm < ?
      ORDER BY nilai LIMIT """ & $RESULTS_LIMIT), fnorm, nextFnorm):
      if row[0] notin seen:
        seen.add(row[0])
        rows.add(row[0])

    if rows.len == 0:
      echo "No results for '" & cmd & "'"
    elif rows.len == 1:
      let row = db.getRow(sql"""
        SELECT id, nilai, word, kind FROM entries WHERE id = ?""", rows[0])
      printEntry(db, parseInt(row[0]), row[1], row[2], row[3])
    else:
      echo "Found " & $rows.len & " results for '" & cmd & "':"
      let displayCount = min(DISPLAY_LIMIT, rows.len)
      let idList = rows[0 ..< displayCount].join(",")
      for row in db.fastRows(sql("""
        SELECT e.id, e.word, COALESCE(s.pos, ''), COALESCE(s.text, ''), COALESCE(se.example, '')
        FROM entries e
        LEFT JOIN (SELECT entry_id, MIN(id) as sid FROM senses GROUP BY entry_id) s1 ON e.id = s1.entry_id
        LEFT JOIN senses s ON s.id = s1.sid
        LEFT JOIN (SELECT sense_id, MIN(id) as exid FROM sense_examples GROUP BY sense_id) se1 ON s.id = se1.sense_id
        LEFT JOIN sense_examples se ON se.id = se1.exid
        WHERE e.id IN (""" & idList & ")")):
        printShort(row[2], row[3], row[4], row[0], row[1])
      if rows.len > DISPLAY_LIMIT: echo "  ... more"

when isMainModule:
  main()