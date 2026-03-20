# Data Types & Binary Format

> Reference guide to Nim data structures for dictionary entries, senses, categories, and parse results.

## Overview

All types are defined in `src/kbbi/types.nim` and used consistently across:
- **Decryption & parsing** (`kbbi_build.nim` → `parser.nim`)
- **SQL database storage** (SQLite schema with entries, senses, xrefs, categories)
- **CLI search** (`kbbi_search.nim`)
- **Web browser** (`kbbi_js.nim`)

These structs define how binary dictionary data is parsed from encrypted files, structured in memory, and stored in the SQLite database.

---

## `Salsa20`

Internal state array for the Salsa20 stream cipher used to decrypt `acu_desc_*.s` files.

```nim
Salsa20 = array[16, uint32]
```

Used exclusively in `src/kbbi/crypto.nim`. Not exposed outside of decryption.

---

## `VStream`

A cursor over a `seq[byte]` for reading the binary entry data stream.

```nim
VStream* = ref object
  data*: seq[byte]
  pos*:  int
```

Constructors:
- `newVStream(data: seq[byte]): VStream`
- `newVStream(data: string): VStream`

Key methods (all in `src/kbbi/varint.nim`):

| proc | description |
|---|---|
| `atEnd()` | returns `true` when `pos >= data.len` |
| `readByte()` | reads one byte, returns `-1` at end |
| `readVarint()` | reads a variable-length integer (see encoding table below) |
| `readRawString(n)` | reads exactly `n` bytes as a string with no intermediate allocation |
| `readString()` | reads a varint length prefix then that many bytes |
| `readUint8()` | alias for `readByte()` |

`readRawString` slices `data` directly rather than copying byte-by-byte, avoiding an intermediate allocation.

---

## `OffLen`

Maps an entry ID to its physical location in the encrypted data files.

```nim
OffLen* = object
  fileIdx*: int   # which acu_desc_N.s file (0..27)
  offset*:  int   # byte offset within that file
```

Loaded from `acu_offlens.txt` which contains one `OffLen` per entry in delta-encoded varint format. Given entry ID `N`, seek to `offset` in `acu_desc_{fileIdx}.s` to read its binary data.

**Implementation detail:** During database building, `kbbi_build.nim` reads `offlens[id-1]` and computes the end offset as `offlens[id].offset` (or end-of-file if at the boundary). This bounds each entry's binary data for parsing.

---

## `Entry`

A single dictionary headword and all its definitions.

```nim
Entry* = ref object
  id*:     int          # 1-based ID (position in acu_nilai)
  word*:   string       # display form with syllable dots, e.g. "a.pa-a.pa.an"
  kind*:   string       # entry type (see below)
  see*:    seq[int]     # redirect target IDs
  senses*: seq[Sense]   # list of definitions
```

Constructor: `newEntry(word="", kind="", id=0): Entry`

### Entry kinds

| kind | description | example |
|---|---|---|
| `normal` | standard dictionary word | `a.ba.di`, `air` |
| `foreign` | foreign expression | `à charge`, `a fortiori` |
| `phrase` | multi-word phrase | `abad keemasan`, `air mata` |
| `nonstandard` | unsyllabified or variant spelling of a group's headword | `Yahweh` sub-entry inside `Yah.we` group |
| `redirect` | points to another entry via `see` | old spelling → correct entry |
| `alias` | phrase entry with no senses and no `see` refs | short form → full form |
| `group` | multiple headwords share one `nilai` slot | `ADP (1)`, `ADP (2)`, `ADP (3)` |

**Why `group`?** The search index stores one key per `nilai` slot. When multiple headwords normalize to the same key (e.g. `ADP (1)`, `ADP (2)`, `ADP (3)` all become `"adp"`), they share one slot and are stored as a group. Each sub-entry's `word` and `kind` are stored on each sense row via `entry_word` and `entry_kind` columns so the frontend can reconstruct the variant grouping.

**Why `nonstandard`?** Used for unsyllabified or phonetic variant spellings within a group entry. For example `Yah.we` (group) contains `Yahweh` (nonstandard) as the sub-entry that actually holds the definitions. The `nonstandard` badge is suppressed in the frontend when a group has only one variant, since the unsyllabified form is just an alternate written form rather than a genuinely incorrect spelling.

**`alias` vs `redirect`:** Both are assigned automatically by `flushEntry()` in `parser.nim` — never set directly by an opcode.
- `alias` = phrase entry where `senses.len == 0` AND `see.len == 0`
- `redirect` = any entry where `senses.len == 0` AND `see.len > 0`

---

## `Sense`

One definition within an entry. An entry can have multiple senses, each with its own category labels.

```nim
Sense* = ref object
  number*:   string        # "1", "2", "3" — empty if only one sense

  # category labels (per-sense)
  pos*:      string        # word class: n, v, a, adv, p, num, pron, ...
  bahasa*:   string        # language of origin: Jw, Ar, Ing, Bld, Sd, Skt, ...
  bidang*:   string        # subject domain: Kim, Bio, Dok, Mus, Huk, ...
  ragam*:    string        # register: cak, ark, kl, kas, vul, of, hor
  markers*:  seq[string]   # type markers: ki, sing, akr, ukp (comma-separated in DB)

  # main content
  text*:     string        # definition text (may be empty when definition is in latin/altText)
  examples*: seq[string]   # example sentences ("--" or "~" = the headword)

  # special content
  altForm*:  string        # syllabified/vowel-marked pronunciation variant
  altText*:  string        # redirect label text ("lihat X")
  latin*:    string        # scientific/Latin name (stored without <i> tags)
  abbrev*:   string        # abbreviation expansion
  link*:     string        # equivalent word
  chem*:     string        # chemical formula (assembled from opcodes 24, 62, 63, 74)

  # cross-references
  xrefs*:      seq[int]          # plain entry ID references (no typed relationship)
  xrefGroups*: seq[XrefGroup]    # typed cross-references
```

Constructor: `newSense(number="", pos="", bahasa="", bidang="", ragam=""): Sense`

**`isBlank` check:** A sense is considered blank when all of `text`, `altForm`, `altText`, `latin`, `abbrev`, `link`, `chem`, `examples`, `markers`, and `xrefGroups` are empty. Blank senses with only plain `xrefs` are promoted to `entry.see` (redirect targets) rather than stored as senses.

**`altForm` note:** In the current KBBI data, `altForm` exclusively contains vowel/syllable-marked forms using circumflex characters (`ê`, `â`, `î`, `ô`, `û`). It is never used for non-standard spellings — those are encoded as separate `nonstandard` kind entries instead.

**`latin` note:** The `<i>` and `</i>` HTML tags that appear in the raw binary data are stripped at serialize time in `parser.nim`'s `senseToJson`. The `latin` field in the DB and in the JSON always contains plain text.

**`text` may be empty:** Some entries (especially scientific terms) store their definition entirely in `latin` rather than `text`. This is valid — `renderSense` in `kbbi_js.nim` handles each field independently.

### Markers

| marker | meaning |
|---|---|
| `ki` | kiasan — figurative / idiomatic usage |
| `sing` | singkatan — abbreviation |
| `akr` | akronim — acronym |
| `ukp` | ungkapan — foreign expression |

---

## `XrefGroup`

Typed cross-reference collection for a single sense.

```nim
XrefGroup* = ref object
  kind*: string       # relationship type (see below)
  refs*: seq[int]     # target entry IDs
```

Constructor: `newXrefGroup(kind="", refs: seq[int]=@[]): XrefGroup`

### Relationship kinds

| kind | opcode | meaning |
|---|---|---|
| `baku` | 10 | bentuk baku — standard/canonical form |
| `dasar` | 11 | kata dasar — base/root word (**see note below**) |
| `turunan` | 12 | kata turunan — derived / affixed forms |
| `lihat` | 13 | lihat juga — see also |
| `gabungan` | 14 | kata gabungan — compound words |
| `peribahasa` | 15 | peribahasa — proverbs containing this word |

> **Note on `dasar` (opcode 11):** Opcode 11 is defined in `CODE_ARG` with arg type `1` (no argument), meaning it should set `xrefKind = "dasar"`. However the `case code` block in `parser.nim` has **no handler** for opcode 11 — it falls through to `else: discard`. As a result, `dasar` xref groups are never populated from the binary data. If base-word relationships appear in the APK, they are silently dropped. This is a known gap.

### Plain xrefs vs xref groups

Plain `xrefs` are bare cross-reference IDs with no typed relationship. They arise from:
- Opcode 41 — always plain regardless of current `xrefKind`
- Opcode 40 — plain when no `xrefKind` is currently set

`xrefGroups` arise from opcode 40 when a kind-setting opcode (10–15) was seen earlier in the current sense. Multiple refs of the same kind are accumulated into the same `XrefGroup` rather than creating duplicate group entries.

`xrefKind` is reset to `""` on every `flushSense()` call, not between individual opcode 40 calls. So a single kind opcode can be followed by multiple opcode 40 calls to accumulate several refs under the same kind.

---

## `Kategori`

A category label from one of the `kat_index_*.txt` files.

```nim
Kategori* = ref object
  nilai*: string   # short code, e.g. "Adm", "Jw", "n", "cak"
  desc*:  string   # full Indonesian label, e.g. "Administrasi dan Kepegawaian"
```

Constructor: `newKategori(nilai="", desc=""): Kategori`

There are five category types (`jenis`): `bahasa`, `bidang`, `ragam`, `kelas`, `jenis`.

---

## Binary encoding (varint)

The index files use a custom variable-length integer encoding defined in `src/kbbi/varint.nim`.

### Varint decoding table

| leading byte | bytes following | value computed |
|---|---|---|
| `0–239` | 0 | the byte itself |
| `254` | 1 (`b`) | `b` |
| `253` | 1 (`b`) | `b \| 256` |
| `252` | 2 (`b1, b2`) | `(b1 << 8) \| b2` |
| `251` | 2 (`b1, b2`) | `(b1 << 8) \| 65536 \| b2` |
| `250` | 3 (`b1, b2, b3`) | `(b1 << 16) \| (b2 << 8) \| b3` |
| any other | — | `-1` (error / end of stream) |

---

## Parser opcodes

The binary entry data in `acu_desc_*.s` (after Salsa20 decryption and gzip decompression) is a stream of opcodes. Each opcode byte has a fixed argument type from the `CODE_ARG` lookup table:

| arg type | meaning |
|---|---|
| `0` | no argument, no-op (default for unmapped opcodes) |
| `1` | no argument |
| `2` | varint argument |
| `3` | length-prefixed string argument |

### Opcode reference

| opcode | arg type | effect |
|---|---|---|
| `0` | string | Text token. On `"\n\n"` → `flushSense()`. On `digit + "."` → `flushSense()`, set `sense.number`. Otherwise append to `sense.text` (ignoring `"\n"`, `" "`, `": "`, `"; "`, `""`) |
| `1` | string | Begin new `phrase` entry |
| `2` | string | Set `sense.altForm` |
| `3` | string | Begin new `normal` entry |
| `4` | string | Begin new `nonstandard` entry |
| `5` | string | Begin new `foreign` entry |
| `10` | — | Set `xrefKind = "baku"` |
| `11` | — | Set `xrefKind = "dasar"` (**defined but not handled** — falls through to `else: discard`) |
| `12` | — | Set `xrefKind = "turunan"` |
| `13` | — | Set `xrefKind = "lihat"` |
| `14` | — | Set `xrefKind = "gabungan"` |
| `15` | — | Set `xrefKind = "peribahasa"` |
| `20` | string | Set `sense.pos` |
| `21` | string | Set `sense.bahasa` |
| `22` | string | Set `sense.bidang` |
| `23` | string | Set `sense.latin` |
| `24` | string | Append to chemical formula buffer |
| `25` | string | Set `sense.ragam` |
| `30` | — | Add marker `ki` |
| `31` | — | Add marker `sing` |
| `32` | — | Add marker `akr` |
| `33` | — | Add marker `ukp` |
| `40` | varint | Add xref — typed (appended to matching `XrefGroup`) if `xrefKind` is set, plain (`sense.xrefs`) otherwise |
| `41` | varint | Add plain xref always (ignores `xrefKind`) |
| `42` | string | Set `sense.altText` |
| `50` | string | Add example sentence to `sense.examples` |
| `60` | string | Set `sense.abbrev` |
| `61` | string | Set `sense.link` |
| `62` | string | Append to chemical formula buffer |
| `63` | string | Append to chemical formula buffer |
| `74` | string | Append to chemical formula buffer |
| `255` | — | Flush current entry |

**Chemical formula buffer:** Opcodes 24, 62, 63, and 74 all append their string argument to `chemBuf`. On `flushChem()` (called at the start of every non-chem opcode handler, and during sense/entry flush), `chemBuf` is concatenated into `sense.chem` and cleared. This assembles multi-part chemical formulas from multiple opcodes.

---

## Parser flow

```text
parse(data: seq[byte]): seq[Entry]
  │
  └── loop over opcodes
        ├── 1 / 3 / 4 / 5   flushEntry(), begin new cur
        ├── 0                flushSense() on "\n\n" or digit+"."
        │                    else append to sense.text
        ├── 10–15            set xrefKind (11 is a no-op bug)
        ├── 20–25            set sense category fields
        ├── 30–33            add marker to sense.markers
        ├── 40 / 41          add xref (typed or plain)
        ├── 42               set sense.altText
        ├── 50               add example
        ├── 60 / 61          set abbrev / link
        ├── 24 / 62 / 63 / 74  append to chemBuf
        └── 255              flushEntry()

flushEntry()
  └── flushSense()
        └── flushChem()   drain chemBuf → sense.chem
        if blank AND xrefs only (no xrefGroups)
          → promote xrefs to cur.see
        else
          → cur.senses.add(sense)
  post-processing:
    phrase + senses.len == 0 + see.len == 0  → kind = "alias"
    senses.len == 0 + see.len > 0            → kind = "redirect"
  entries.add(cur)
```