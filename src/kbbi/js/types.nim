import karax/[kbase]

type SearchMode* = enum
  ModeAuto
  ModePrefix
  ModeFts
  ModeKatKelas
  ModeKatBahasa
  ModeKatBidang
  ModeKatRagam
  ModeListKelas
  ModeListBahasa
  ModeListBidang
  ModeListRagam

type AppState* = object
  mode*: SearchMode
  query*: kstring
  katFilter*: kstring
  resultHtml*: kstring
  hasResult*: bool
  isLoading*: bool
  isDbReady*: bool
  dbError*: kstring
  dropdownOpen*: bool
  highlightedIdx*: int

type DropdownItem* = object
  value*: SearchMode
  label*: kstring
  hint*: kstring
  group*: kstring
  isCyan*: bool
  isMag*: bool
