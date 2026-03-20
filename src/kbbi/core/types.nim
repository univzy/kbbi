type
  OffLen* = object
    fileIdx*: int
    offset*: int

  XrefGroup* = ref object
    kind*: string
    refs*: seq[int]

  Sense* = ref object
    number*: string
    pos*: string
    bahasa*: string
    bidang*: string
    ragam*: string
    markers*: seq[string]
    text*: string
    altForm*: string
    altText*: string
    latin*: string
    abbrev*: string
    link*: string
    chem*: string
    examples*: seq[string]
    xrefs*: seq[int]
    xrefGroups*: seq[XrefGroup]

  Entry* = ref object
    id*: int
    word*: string
    kind*: string
    see*: seq[int]
    senses*: seq[Sense]

  Kategori* = ref object
    nilai*: string
    desc*: string

proc newSense*(
    number = "", pos = "", bahasa = "", bidang = "", ragam = ""): Sense =
  let s = new(Sense)
  s.number = number
  s.pos = pos
  s.bahasa = bahasa
  s.bidang = bidang
  s.ragam = ragam
  s.markers = @[]
  s.text = ""
  s.altForm = ""
  s.altText = ""
  s.latin = ""
  s.abbrev = ""
  s.link = ""
  s.chem = ""
  s.examples = @[]
  s.xrefs = @[]
  s.xrefGroups = @[]
  s

proc newEntry*(word = "", kind = "", id = 0): Entry =
  let e = new(Entry)
  e.word = word
  e.kind = kind
  e.id = id
  e.see = @[]
  e.senses = @[]
  e

proc newKategori*(nilai = "", desc = ""): Kategori =
  let k = new(Kategori)
  k.nilai = nilai
  k.desc = desc
  k

proc newXrefGroup*(kind = "", refs: seq[int] = @[]): XrefGroup =
  let g = new(XrefGroup)
  g.kind = kind
  g.refs = refs
  g