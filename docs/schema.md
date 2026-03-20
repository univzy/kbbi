# SQLite Database Schema

> Relational database design for efficient storage and querying of 100,000+ dictionary entries.

## Overview

`kbbi.db` is a standard SQLite database built by `kbbi_build`. It contains all dictionary entries in a fully relational structure — no JSON blobs, no flat comma-separated columns.

---

## Tables

### `entries`

One row per `nilai` slot (headword lookup key).

```sql
CREATE TABLE entries (
  id         INTEGER PRIMARY KEY,  -- 1-based, matches acu_nilai position
  nilai      TEXT NOT NULL,        -- normalized search key, lowercase (e.g. "abadi")
  nilai_norm TEXT NOT NULL,        -- fuzzy key, alphanumeric only (e.g. "apaapa")
  word       TEXT NOT NULL,        -- display form with syllable dots (e.g. "a.ba.di")
  kind       TEXT NOT NULL         -- normal|foreign|phrase|nonstandard|redirect|alias|group
)
```

**`nilai` vs `nilai_norm`:** `nilai` is the lowercase form preserving hyphens and spaces. `nilai_norm` strips all non-alphanumeric characters. This allows fuzzy prefix search — typing `"apa apaan"` or `"apaapaan"` both find `"apa-apaan"`.

### `senses`

One row per definition sense. Multiple senses per entry are common.

```sql
CREATE TABLE senses (
  id         INTEGER PRIMARY KEY,
  entry_id   INTEGER NOT NULL,   -- FK → entries.id
  entry_word TEXT NOT NULL,      -- sub-entry word (for group entries)
  entry_kind TEXT NOT NULL,      -- sub-entry kind (for group entries)
  number     TEXT NOT NULL,      -- sense number: "1", "2", "" if only one
  pos        TEXT NOT NULL,      -- word class: n, v, a, adv, ...
  bahasa     TEXT NOT NULL,      -- language of origin: Jw, Ar, Ing, ...
  bidang     TEXT NOT NULL,      -- subject domain: Kim, Bio, Dok, ...
  ragam      TEXT NOT NULL,      -- register: cak, ark, kl, ...
  markers    TEXT NOT NULL,      -- comma-separated: ki, sing, akr, ukp
  text       TEXT NOT NULL,      -- definition text
  altForm    TEXT NOT NULL,      -- non-standard spelling variant
  altText    TEXT NOT NULL,      -- redirect label ("lihat X")
  latin      TEXT NOT NULL,      -- scientific/Latin name
  abbrev     TEXT NOT NULL,      -- abbreviation expansion
  link       TEXT NOT NULL,      -- equivalent word
  chem       TEXT NOT NULL,      -- chemical formula
  FOREIGN KEY (entry_id) REFERENCES entries(id)
)
```

**Why `entry_word` and `entry_kind` on senses?** For `group` entries, multiple sub-entries share one `entry_id`. Storing the sub-entry's word and kind on each sense row allows the frontend to reconstruct the variant grouping in a single query without a separate join.

### `sense_examples`

Example sentences, one per row.

```sql
CREATE TABLE sense_examples (
  id       INTEGER PRIMARY KEY,
  sense_id INTEGER NOT NULL,   -- FK → senses.id
  example  TEXT NOT NULL       -- "--" or "~" in text = the headword placeholder
)
```

### `sense_xrefs`

Plain cross-references (no typed relationship).

```sql
CREATE TABLE sense_xrefs (
  id       INTEGER PRIMARY KEY,
  sense_id INTEGER NOT NULL,   -- FK → senses.id
  xref_id  INTEGER NOT NULL    -- FK → entries.id
)
```

### `sense_xref_groups`

Typed cross-references. One row per (sense, kind, target entry).

```sql
CREATE TABLE sense_xref_groups (
  id       INTEGER PRIMARY KEY,
  sense_id INTEGER NOT NULL,   -- FK → senses.id
  kind     TEXT NOT NULL,      -- baku|dasar|lihat|turunan|gabungan|peribahasa
  ref_id   INTEGER NOT NULL    -- FK → entries.id
)
```

### `kategori_*`

Five separate tables, one per category type.

```sql
CREATE TABLE kategori_bahasa ( nilai TEXT PRIMARY KEY, desc TEXT NOT NULL )
CREATE TABLE kategori_bidang ( nilai TEXT PRIMARY KEY, desc TEXT NOT NULL )
CREATE TABLE kategori_ragam  ( nilai TEXT PRIMARY KEY, desc TEXT NOT NULL )
CREATE TABLE kategori_kelas  ( nilai TEXT PRIMARY KEY, desc TEXT NOT NULL )
CREATE TABLE kategori_jenis  ( nilai TEXT PRIMARY KEY, desc TEXT NOT NULL )
```

### `kategori_counts`

Precomputed entry counts per category code. Populated at build time to avoid expensive runtime `LIKE` scans in the list view.

```sql
CREATE TABLE kategori_counts (
  jenis TEXT NOT NULL,   -- bahasa|bidang|ragam|kelas|jenis
  nilai TEXT NOT NULL,   -- category code
  cnt   INTEGER NOT NULL,
  PRIMARY KEY (jenis, nilai)
)
```

Without this table, `searchList` would run a full `LIKE '%,value,%'` scan across the entire `senses` table for every category row — noticeably slow on large datasets. The counts are computed once during `kbbi_build` and are instant to look up at query time.

### `entries_fts`

FTS5 virtual table for full-text search across headwords and definition texts.

```sql
CREATE VIRTUAL TABLE entries_fts USING fts5(
  word, text,
  content = entries,
  content_rowid = id
)
```

The `text` column is populated with a `trim(group_concat(...))` of all non-empty sense texts and their examples. Empty senses are excluded via `CASE WHEN s.text != ''` to avoid trailing spaces in the indexed content.

---

## Indexes

```sql
CREATE INDEX idx_entries_nilai        ON entries(nilai)
CREATE INDEX idx_entries_nilai_norm   ON entries(nilai_norm)
CREATE INDEX idx_senses_entry_id      ON senses(entry_id)
CREATE INDEX idx_senses_pos           ON senses(pos)
CREATE INDEX idx_senses_bahasa        ON senses(bahasa)
CREATE INDEX idx_senses_bidang        ON senses(bidang)
CREATE INDEX idx_senses_ragam         ON senses(ragam)
CREATE INDEX idx_senses_markers       ON senses(markers)
CREATE INDEX idx_examples_sense_id    ON sense_examples(sense_id)
CREATE INDEX idx_xrefs_sense_id       ON sense_xrefs(sense_id)
CREATE INDEX idx_xref_groups_sense_id ON sense_xref_groups(sense_id)
```

---

## Search strategy

### Prefix search (`prefix` / Awalan mode)

Two passes, results deduped by ID using a Nim `seq[cstring]` with `contains`:

1. **Pass 1 — exact `nilai` prefix:** `nilai >= ? AND nilai < nextChar(?)` — preserves hyphens and spaces.
2. **Pass 2 — fuzzy `nilai_norm` prefix:** strips non-alphanumeric before comparing.

### Exact match (`auto` / Otomatis mode)

Tries `WHERE nilai = ?` first, then `WHERE nilai_norm = ?` as fuzzy fallback. Falls back to prefix search if nothing found.

### Category filter (`kat-*` modes)

```sql
WHERE (',' || s.pos || ',') LIKE '%,' || ? || ',%'
```

The comma-wrapping pattern ensures `"n"` doesn't accidentally match `"num"`. An optional word prefix clause is added when the main search input is non-empty:

```sql
AND e.nilai >= ? AND e.nilai < nextChar(?)
```

### Full-text search (`fts` / Teks penuh mode)

Standard FTS5 `MATCH` query against `entries_fts`. User input is wrapped in double-quotes before querying to prevent FTS5 syntax errors from operators or unmatched quotes.

### Sense fetching (browser only)

The browser fetches all child data for an entry in 4 queries — senses, examples, xrefs, xref_groups — rather than one query per sense row. Results are partitioned by `sense_id` in JS, avoiding N+1 queries.