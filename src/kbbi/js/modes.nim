import karax/[kbase]
import ./[types]

proc isKatMode*(m: SearchMode): bool =
  m in {ModeKatKelas, ModeKatBahasa, ModeKatBidang, ModeKatRagam}

proc isListMode*(m: SearchMode): bool =
  m in {ModeListKelas, ModeListBahasa, ModeListBidang, ModeListRagam}

proc katFilterLabel*(m: SearchMode): kstring =
  case m
  of ModeKatKelas: "kelas kata"
  of ModeKatBahasa: "bahasa"
  of ModeKatBidang: "bidang"
  of ModeKatRagam: "ragam"
  else: ""

proc modeToString*(m: SearchMode): kstring =
  case m
  of ModeAuto: "auto"
  of ModePrefix: "prefix"
  of ModeFts: "fts"
  of ModeKatKelas: "kat-kelas"
  of ModeKatBahasa: "kat-bahasa"
  of ModeKatBidang: "kat-bidang"
  of ModeKatRagam: "kat-ragam"
  of ModeListKelas: "list-kelas"
  of ModeListBahasa: "list-bahasa"
  of ModeListBidang: "list-bidang"
  of ModeListRagam: "list-ragam"

const dropdownItems*: seq[DropdownItem] = @[
  DropdownItem(value: ModeAuto, label: "Otomatis", hint: "auto", group: "mode"),
  DropdownItem(value: ModePrefix, label: "Awalan", hint: "prefix", group: "mode"),
  DropdownItem(value: ModeFts, label: "Teks penuh", hint: "fulltext", group: "mode"),
  DropdownItem(
    value: ModeKatKelas, label: "Kelas kata", hint: "kat", group: "filter", isCyan: true
  ),
  DropdownItem(
    value: ModeKatBahasa, label: "Bahasa", hint: "kat", group: "filter", isCyan: true
  ),
  DropdownItem(
    value: ModeKatBidang, label: "Bidang", hint: "kat", group: "filter", isCyan: true
  ),
  DropdownItem(
    value: ModeKatRagam, label: "Ragam", hint: "kat", group: "filter", isCyan: true
  ),
  DropdownItem(
    value: ModeListKelas,
    label: "Daftar kelas kata",
    hint: "list",
    group: "daftar",
    isMag: true,
  ),
  DropdownItem(
    value: ModeListBahasa,
    label: "Daftar bahasa",
    hint: "list",
    group: "daftar",
    isMag: true,
  ),
  DropdownItem(
    value: ModeListBidang,
    label: "Daftar bidang",
    hint: "list",
    group: "daftar",
    isMag: true,
  ),
  DropdownItem(
    value: ModeListRagam,
    label: "Daftar ragam",
    hint: "list",
    group: "daftar",
    isMag: true,
  ),
]

proc modeLabel*(m: SearchMode): kstring =
  for item in dropdownItems:
    if item.value == m:
      return item.label
  return ""
