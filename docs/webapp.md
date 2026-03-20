# Web App Guide

> Browser-based dictionary interface with offline caching, full-text search, and category filtering.

## Overview

The browser dictionary runs entirely offline after the first load. There is no server, no API, and no internet connection required for search.

---

## Architecture

```text
pages/index.html + style.css    shell and styles
      │
      ├── pages/kbbi.js         compiled from src/kbbi_js.nim (Nim → JS)
      │     │
      │     └── sql.js-fts5     SQLite compiled to WebAssembly (FTS5 enabled)
      │
      └── pages/kbbi.db         fetched once, cached in Cache API
```

`kbbi.js` is compiled from `src/kbbi_js.nim` using Nim's JavaScript backend (`nim js`). It handles all search logic, SQL queries via sql.js, and HTML rendering. No npm, no bundler, no runtime dependencies beyond the compiled output.

---

## Database caching

`kbbi.db` is fetched once on first load and stored in the browser's [Cache API](https://developer.mozilla.org/en-US/docs/Web/API/Cache) under a versioned key defined in `src/kbbi/config.nim`:

```nim
# src/kbbi/config.nim
const KbbiVersion* = "0.0.1"
const CACHE_KEY = "kbbi_cache_vi_" & KbbiVersion
```

On subsequent page loads the cached DB is served immediately — no network request. Download progress is tracked via `ReadableStream` and displayed in the load bar. To force all users to re-download (e.g. after shipping a new `kbbi.db`), bump `KbbiVersion` in `version.nim` and rebuild.

The Cache API requires a secure context (HTTPS or localhost). If opened as `file://`, the code falls back to a plain `fetch()` without caching.

---

## Search modes

| Mode | UI label | Query method |
|---|---|---|
| `auto` | Otomatis | Exact `nilai` match first, then fuzzy `nilai_norm` match, fallback to prefix search |
| `prefix` | Awalan | Two-pass prefix search (exact `nilai` + fuzzy `nilai_norm`), deduped by seq contains |
| `fts` | Teks penuh | FTS5 full-text search with auto-quoting user input |
| `kat-kelas` | Kelas kata | Filter `senses` WHERE comma-wrapped `pos` LIKE pattern |
| `kat-bahasa` | Bahasa | Same pattern with `bahasa` column |
| `kat-bidang` | Bidang | Same pattern with `bidang` column |
| `kat-ragam` | Ragam | Same pattern with `ragam` column |
| `list-kelas` | Daftar kelas kata | SELECT from `kategori_kelas` JOIN `kategori_counts` |
| `list-bahasa` | Daftar bahasa | SELECT from `kategori_bahasa` JOIN `kategori_counts` |
| `list-bidang` | Daftar bidang | SELECT from `kategori_bidang` JOIN `kategori_counts` |
| `list-ragam` | Daftar ragam | SELECT from `kategori_ragam` JOIN `kategori_counts` |

For `kat-*` modes, a second input row appears for the category filter code. Both word and code inputs can be combined — e.g., word `apa` + bahasa `Jw`.

### Auto mode fallback

`auto` mode tries exact match first, then prefix search. Both return a `(html, found: bool)` tuple — the fallback uses the `found` boolean, never string inspection:

```
searchExact(query) → (html, found)
  if found        → show result
  else            → searchPrefix(query) → (html, found)
                    if found  → show prefix results
                    else      → show not-found from exact search
```

---

## Safety & Query Protection

### FTS5 Safety

Raw user input passed to `entries_fts MATCH ?` would be parsed by FTS5 as a query expression — operators like `OR`, `AND`, `-`, and unmatched quotes cause parse errors.

To prevent this, input is wrapped in double-quotes and internal quotes are escaped:

```
user types:   can't "find" it
safe query:   "can't ""find"" it"
```

Passed as a parameterized `?` binding.

### Category Filter Safety

Category columns (`pos`, `bahasa`, `bidang`, `ragam`, `markers`) can contain comma-separated values (e.g., `pos = "n,v"`). Searching for `"n"` without wrapping would match `"nav"`.

Safe pattern:
```sql
WHERE (',' || s.pos || ',') LIKE '%,' || ? || ',%'
```

All user input is parameterized binding — no string interpolation into SQL.

---

## Sense fetching

The browser fetches all child data for an entry in **4 queries** rather than one query per sense row, avoiding N+1 queries:

1. All senses for the entry (`ORDER BY id`)
2. All examples for those sense IDs (`IN (...)`)
3. All plain xrefs for those sense IDs
4. All xref groups for those sense IDs

Results are partitioned by `sense_id` in JS, then assembled into sense objects. For `group` entries, senses are further grouped by `(entry_word, entry_kind)` to reconstruct variants.

---

## Word cache (LRU)

`lookupWordById(id)` is called during xref rendering to resolve entry IDs to display words. To avoid repeated SQL queries for the same ID, results are stored in a pure Nim LRU cache:

```nim
type LRUCache = object
  entries: seq[(cstring, cstring)]  # (key, value) pairs, most-recent at index 0
  maxSize: int                      # MAX_WORD_CACHE_SIZE = 150
```

On hit, the entry is moved to front. On eviction, the last entry (least recently used) is dropped. At 150 entries and linear scan, overhead is negligible.

---

## Exported JS functions

These are the Nim procs exported with `{.exportc.}` and callable from the page:

| function | called by | description |
|---|---|---|
| `doSearch()` | search button, Enter key | reads both inputs, runs current mode |
| `nimSearch(word)` | inline definition links, history items | searches for `word` in `auto` mode, updates input |
| `nimSearchById(id)` | word-list chips, xref buttons | fetches and renders entry by integer ID, updates search input and history |
| `nimKat(jenis, nilai)` | category list chips | switches to `kat-{jenis}` mode, sets filter input, clears word input, runs search |
| `loadHistoryFromStorage()` | called on `window.onload` | restores search history from `localStorage` |
| `clearHistory()` | clear history button | clears history from memory and `localStorage` |

`nimKat` also updates the custom dropdown and shows the filter row so the UI stays in sync — pressing Enter after clicking a category chip correctly re-runs the same filter.

---

## Search history

Search history is stored in `localStorage` under the key `kbbi_search_history` as a JSON array of up to `MAX_HISTORY = 8` items. Items are JSON-escaped with `jsStrEsc` (not `htmlEsc`) to avoid corrupting the stored JSON.

On load, history is restored and rendered as clickable chips. Clicking a chip calls `nimSearch(word)`. The clear button calls `clearHistory()` which empties both the in-memory `seq` and `localStorage`.

---

## Service Worker

A service worker (`sw.js`) caches the app shell (`index.html`, `style.css`, `kbbi.js`) for offline use. It uses cache-first strategy for shell assets.

**Important:** `kbbi.db` is intentionally **not** intercepted by the service worker — the app's own Cache API (keyed by `CACHE_KEY`) manages DB caching independently. The SW's activate handler preserves any cache whose name starts with `kbbi_cache` to avoid evicting the DB cache when the shell cache version is bumped.

Cache version constants:

| constant | location | controls |
|---|---|---|
| `CACHE_VERSION` in `sw.js` | `sw.js` | shell cache (`index.html`, `style.css`, `kbbi.js`) |
| `KbbiVersion` in `version.nim` | `src/kbbi/config.nim` | database cache (`kbbi.db`) |

Bump `CACHE_VERSION` when the UI/JS changes. Bump `KbbiVersion` when `kbbi.db` changes. They are independent.