import std/[os, strformat, strutils, tables]
import pkg/[db_connector/db_sqlite]
import kbbi/core/[types, crypto, index, parser, common]

const
  descFilesCount = 28
  batchCommitSize = 10000

proc parseEntriesAt(data: seq[byte], fromOff: int, toOff: int): seq[Entry] =
  if fromOff < 0 or fromOff > data.len:
    raise newException(ValueError, "Invalid description offset")
  let endOff =
    if toOff > fromOff:
      min(toOff, data.len)
    else:
      data.len
  let slice = data[fromOff ..< endOff]
  result = parse(slice)

proc main() =
  if paramCount() < 2:
    echo "Usage: kbbi_build_sqlite <dictdata_dir> <output.db>"
    quit(1)

  let dictDir = paramStr(1)
  let outPath = paramStr(2)

  if not dirExists(dictDir):
    echo "ERROR: Dictionary directory not found: " & dictDir
    quit(1)

  if fileExists(outPath):
    try:
      removeFile(outPath)
    except Exception as e:
      echo fmt"WARNING: Could not remove existing {outPath}: {e.msg}"

  echo "Loading acu_nilai..."
  let nilaiPath = dictDir / "acu_nilai.txt"
  if not fileExists(nilaiPath):
    echo "ERROR: File not found: " & nilaiPath
    quit(1)
  let nilais = parseNilai(cast[seq[byte]](readFile(nilaiPath)))
  echo fmt"  {nilais.len} headwords"

  echo "Loading acu_offlens..."
  let offlensPath = dictDir / "acu_offlens.txt"
  if not fileExists(offlensPath):
    echo "ERROR: File not found: " & offlensPath
    quit(1)
  let offlens = parseOfflens(cast[seq[byte]](readFile(offlensPath)))
  echo fmt"  {offlens.len} entries"

  echo "Decrypting desc files..."
  var descData = initTable[int, seq[byte]]()
  for i in 0 ..< descFilesCount:
    let path = dictDir / fmt"acu_desc_{i}.s"
    if not fileExists(path):
      raise newException(IOError, "Missing description file: " & path)
    try:
      descData[i] = decryptFile(path)
      echo fmt"  acu_desc_{i}.s -> {descData[i].len} bytes"
    except Exception as e:
      raise newException(IOError, fmt"Error decrypting {path}: {e.msg}")

  echo fmt"Creating {outPath}..."
  let db = open(outPath, "", "", "")
  defer:
    db.close()

  db.exec(sql"PRAGMA journal_mode = WAL")
  db.exec(sql"PRAGMA synchronous = NORMAL")
  db.exec(sql"PRAGMA cache_size = -64000")
  db.exec(sql"PRAGMA temp_store = MEMORY")

  db.exec(
    sql"""
    CREATE TABLE entries (
      id         INTEGER PRIMARY KEY,
      nilai      TEXT    NOT NULL,
      nilai_norm TEXT    NOT NULL,
      word       TEXT    NOT NULL,
      kind       TEXT    NOT NULL
    )"""
  )

  db.exec(
    sql"""
    CREATE TABLE senses (
      id         INTEGER PRIMARY KEY,
      entry_id   INTEGER NOT NULL,
      entry_word TEXT    NOT NULL DEFAULT '',
      entry_kind TEXT    NOT NULL DEFAULT '',
      number     TEXT    NOT NULL,
      pos        TEXT    NOT NULL,
      bahasa     TEXT    NOT NULL,
      bidang     TEXT    NOT NULL,
      ragam      TEXT    NOT NULL,
      markers    TEXT    NOT NULL,
      text       TEXT    NOT NULL,
      altForm    TEXT    NOT NULL,
      altText    TEXT    NOT NULL,
      latin      TEXT    NOT NULL,
      abbrev     TEXT    NOT NULL,
      link       TEXT    NOT NULL,
      chem       TEXT    NOT NULL,
      FOREIGN KEY (entry_id) REFERENCES entries(id)
    )"""
  )

  db.exec(
    sql"""
    CREATE TABLE sense_examples (
      id       INTEGER PRIMARY KEY,
      sense_id INTEGER NOT NULL,
      example  TEXT    NOT NULL,
      FOREIGN KEY (sense_id) REFERENCES senses(id)
    )"""
  )

  db.exec(
    sql"""
    CREATE TABLE sense_xrefs (
      id       INTEGER PRIMARY KEY,
      sense_id INTEGER NOT NULL,
      xref_id  INTEGER NOT NULL,
      FOREIGN KEY (sense_id) REFERENCES senses(id),
      FOREIGN KEY (xref_id) REFERENCES entries(id)
    )"""
  )

  db.exec(
    sql"""
    CREATE TABLE sense_xref_groups (
      id       INTEGER PRIMARY KEY,
      sense_id INTEGER NOT NULL,
      kind     TEXT    NOT NULL,
      ref_id   INTEGER NOT NULL,
      FOREIGN KEY (sense_id) REFERENCES senses(id),
      FOREIGN KEY (ref_id) REFERENCES entries(id)
    )"""
  )

  db.exec(
    sql"""
    CREATE TABLE kategori_bahasa (
      nilai TEXT NOT NULL PRIMARY KEY,
      desc  TEXT NOT NULL
    )"""
  )

  db.exec(
    sql"""
    CREATE TABLE kategori_bidang (
      nilai TEXT NOT NULL PRIMARY KEY,
      desc  TEXT NOT NULL
    )"""
  )

  db.exec(
    sql"""
    CREATE TABLE kategori_ragam (
      nilai TEXT NOT NULL PRIMARY KEY,
      desc  TEXT NOT NULL
    )"""
  )

  db.exec(
    sql"""
    CREATE TABLE kategori_kelas (
      nilai TEXT NOT NULL PRIMARY KEY,
      desc  TEXT NOT NULL
    )"""
  )

  db.exec(
    sql"""
    CREATE TABLE kategori_jenis (
      nilai TEXT NOT NULL PRIMARY KEY,
      desc  TEXT NOT NULL
    )"""
  )

  echo "Inserting kategori..."
  db.exec(sql"BEGIN")
  try:
    for jenis in ["bahasa", "bidang", "ragam", "kelas", "jenis"]:
      let path = dictDir / fmt"kat_index_{jenis}.txt"
      if not fileExists(path):
        continue
      let cats = parseKatIndex(cast[seq[byte]](readFile(path)))
      let tableName = "kategori_" & jenis
      for c in cats:
        db.exec(sql("INSERT INTO " & tableName & " VALUES (?,?)"), c.nilai, c.desc)
      echo fmt"  {jenis}: {cats.len} categories"
    db.exec(sql"COMMIT")
  except Exception as e:
    echo fmt"ERROR inserting kategori: {e.msg}"
    db.exec(sql"ROLLBACK")
    raise

  echo fmt"Inserting {offlens.len} entries..."
  db.exec(sql"BEGIN")

  var done = 0
  try:
    for id in 1 .. offlens.len:
      let ol = offlens[id - 1]
      let nilai = nilais[id - 1]

      let nextOff =
        if id < offlens.len and offlens[id].fileIdx == ol.fileIdx:
          offlens[id].offset
        else:
          0

      if ol.fileIdx notin descData:
        raise
          newException(ValueError, fmt"Invalid fileIdx={ol.fileIdx} for entry id={id}")
      let entries = parseEntriesAt(descData[ol.fileIdx], ol.offset, nextOff)

      let word =
        if entries.len > 0:
          entries[0].word
        else:
          nilai
      let kind =
        if entries.len > 1:
          "group"
        elif entries.len == 1:
          entries[0].kind
        else:
          "normal"

      db.exec(
        sql"INSERT INTO entries (id, nilai, nilai_norm, word, kind) VALUES (?, ?, ?, ?, ?)",
        id,
        nilai,
        fuzzyNorm(nilai),
        word,
        kind,
      )

      for entry in entries:
        for sense in entry.senses:
          let senseId = db.insertID(
            sql"""
            INSERT INTO senses (entry_id, entry_word, entry_kind, number, pos, bahasa, bidang, ragam, markers, text, altForm, altText, latin, abbrev, link, chem)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            id,
            entry.word,
            entry.kind,
            sense.number,
            sense.pos,
            sense.bahasa,
            sense.bidang,
            sense.ragam,
            sense.markers.join(","),
            sense.text,
            sense.altForm,
            sense.altText,
            sense.latin,
            sense.abbrev,
            sense.link,
            sense.chem,
          )

          for example in sense.examples:
            db.exec(
              sql"INSERT INTO sense_examples (sense_id, example) VALUES (?, ?)",
              senseId,
              example,
            )

          for xref in sense.xrefs:
            db.exec(
              sql"INSERT INTO sense_xrefs (sense_id, xref_id) VALUES (?, ?)",
              senseId,
              xref,
            )

          for group in sense.xrefGroups:
            for refId in group.refs:
              db.exec(
                sql"INSERT INTO sense_xref_groups (sense_id, kind, ref_id) VALUES (?, ?, ?)",
                senseId,
                group.kind,
                refId,
              )

      inc done
      if done mod batchCommitSize == 0:
        db.exec(sql"COMMIT")
        db.exec(sql"BEGIN")
        echo fmt"  {done}/{offlens.len}..."

    db.exec(sql"COMMIT")
  except Exception as e:
    echo fmt"ERROR during insertion at entry {done}: {e.msg}"
    db.exec(sql"ROLLBACK")
    raise

  echo "Creating indexes..."
  db.exec(sql"CREATE INDEX idx_entries_nilai ON entries(nilai)")
  db.exec(sql"CREATE INDEX idx_entries_nilai_norm ON entries(nilai_norm)")
  db.exec(sql"CREATE INDEX idx_senses_entry_id ON senses(entry_id)")
  db.exec(sql"CREATE INDEX idx_senses_pos ON senses(pos)")
  db.exec(sql"CREATE INDEX idx_senses_bahasa ON senses(bahasa)")
  db.exec(sql"CREATE INDEX idx_senses_bidang ON senses(bidang)")
  db.exec(sql"CREATE INDEX idx_senses_ragam ON senses(ragam)")
  db.exec(sql"CREATE INDEX idx_senses_markers ON senses(markers)")
  db.exec(sql"CREATE INDEX idx_examples_sense_id ON sense_examples(sense_id)")
  db.exec(sql"CREATE INDEX idx_xrefs_sense_id ON sense_xrefs(sense_id)")
  db.exec(sql"CREATE INDEX idx_xref_groups_sense_id ON sense_xref_groups(sense_id)")

  echo "Building FTS5 index..."
  db.exec(
    sql"""
    CREATE VIRTUAL TABLE entries_fts USING fts5(
      word, text,
      content = entries,
      content_rowid = id
    )"""
  )
  db.exec(
    sql"""
    INSERT INTO entries_fts(rowid, word, text)
    SELECT
      e.id,
      e.word,
      trim(group_concat(
        case when s.text != '' then
          s.text || coalesce(
            ' ' || (SELECT group_concat(example, ' ')
                    FROM sense_examples
                    WHERE sense_id = s.id),
            '')
        end,
        ' '))
    FROM entries e
    LEFT JOIN senses s ON e.id = s.entry_id
    GROUP BY e.id"""
  )

  echo "Building kategori_counts..."
  db.exec(
    sql"""
    CREATE TABLE kategori_counts (
      jenis TEXT NOT NULL,
      nilai TEXT NOT NULL,
      cnt   INTEGER NOT NULL,
      PRIMARY KEY (jenis, nilai)
    )"""
  )
  for jenis in [
    ("bahasa", "bahasa"),
    ("bidang", "bidang"),
    ("ragam", "ragam"),
    ("kelas", "pos"),
    ("jenis", "markers"),
  ]:
    let (jenisName, col) = jenis
    db.exec(
      sql(
        "INSERT INTO kategori_counts (jenis, nilai, cnt) " & "SELECT '" & jenisName &
          "', k.nilai, COUNT(DISTINCT e.id) " & "FROM kategori_" & jenisName & " k " &
          "LEFT JOIN senses s ON (',' || s." & col &
          " || ',') LIKE '%,' || k.nilai || ',%' " &
          "LEFT JOIN entries e ON s.entry_id = e.id " & "GROUP BY k.nilai"
      )
    )
    echo fmt"  {jenisName}: done"

  db.exec(sql"PRAGMA optimize")

  let sz = getFileSize(outPath)
  echo fmt"Done! {sz div 1024 div 1024} MB -> {outPath}"

when isMainModule:
  main()
