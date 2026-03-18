import std/[json, strutils]
import ./[types, varint]

func isBlank(s: Sense): bool =
  s.text.len == 0 and s.altForm.len == 0 and s.altText.len == 0 and
  s.latin.len == 0 and s.abbrev.len == 0 and s.link.len == 0 and
  s.chem.len == 0 and s.examples.len == 0 and s.markers.len == 0 and
  s.xrefGroups.len == 0

proc senseToJson*(s: Sense): JsonNode =
  result = newJObject()
  if s.number.len > 0:
    result["number"] = %s.number
  if s.pos.len > 0:
    result["pos"] = %s.pos
  if s.bahasa.len > 0:
    result["bahasa"] = %s.bahasa
  if s.bidang.len > 0:
    result["bidang"] = %s.bidang
  if s.ragam.len > 0:
    result["ragam"] = %s.ragam
  if s.markers.len > 0:
    result["markers"] = %s.markers.join(",")
  if s.text.len > 0:
    result["text"] = %s.text
  if s.altForm.len > 0:
    result["alt_form"] = %s.altForm
  if s.altText.len > 0:
    result["alt_text"] = %s.altText
  if s.latin.len > 0:
    result["latin"] = %s.latin.replace("<i>", "").replace("</i>", "")
  if s.abbrev.len > 0:
    result["abbrev"] = %s.abbrev
  if s.link.len > 0:
    result["link"] = %s.link
  if s.chem.len > 0:
    result["chem"] = %s.chem
  if s.examples.len > 0:
    let a = newJArray()
    for e in s.examples:
      a.add(%e)
    result["examples"] = a
  if s.xrefs.len > 0:
    let a = newJArray()
    for x in s.xrefs:
      a.add(%x)
    result["xrefs"] = a
  if s.xrefGroups.len > 0:
    let a = newJArray()
    for g in s.xrefGroups:
      let go = newJObject()
      go["kind"] = %g.kind
      let ra = newJArray()
      for x in g.refs:
        ra.add(%x)
      go["refs"] = ra
      a.add(go)
    result["xref_groups"] = a

proc sensesToJson*(entries: seq[Entry]): string =
  if entries.len == 0:
    return "[]"
  if entries.len == 1:
    let arr = newJArray()
    for s in entries[0].senses:
      arr.add(s.senseToJson())
    return $arr
  let root = newJObject()
  root["group"] = %true
  let variants = newJArray()
  for e in entries:
    let v = newJObject()
    v["word"] = %e.word
    v["kind"] = %e.kind
    let sa = newJArray()
    for s in e.senses:
      sa.add(s.senseToJson())
    v["senses"] = sa
    variants.add(v)
  root["variants"] = variants
  return $root

proc parse*(data: seq[byte]): seq[Entry] =
  var entries: seq[Entry] = @[]
  var s = newVStream(data)
  var cur     = newEntry()
  var hasCur  = false
  var sense   = newSense()
  var xrefKind = ""
  var chemBuf  = ""
  proc flushChem() =
    if chemBuf.len > 0:
      if sense.chem.len > 0:
        sense.chem.add(chemBuf)
      else:
        sense.chem = chemBuf
      chemBuf = ""
  proc flushSense() =
    flushChem()
    if not sense.isBlank or sense.xrefs.len > 0:
      if sense.isBlank and sense.xrefs.len > 0 and sense.xrefGroups.len == 0:
        for x in sense.xrefs:
          cur.see.add(x)
      else:
        cur.senses.add(sense)
    sense = newSense()
    xrefKind = ""
  proc flushEntry() =
    if hasCur:
      flushSense()
      if cur.kind == "phrase" and cur.senses.len == 0 and cur.see.len == 0:
        cur.kind = "alias"
      elif cur.senses.len == 0 and cur.see.len > 0:
        cur.kind = "redirect"
      entries.add(cur)
    cur = newEntry()
    hasCur = false
    sense = newSense()
    xrefKind = ""
    chemBuf = ""
  while not s.atEnd():
    let b = s.readByte()
    if b < 0: break
    let code = b
    let argType = CODE_ARG[code]

    var argNum = 0
    var argStr = ""

    case argType
    of 1:
      discard
    of 2:
      argNum = s.readVarint()
      if argNum < 0: break
    of 3:
      argStr = s.readString()
    else:
      discard

    case code

    of 3:
      flushEntry()
      cur = newEntry(argStr, "normal")
      hasCur = true

    of 5:
      flushEntry()
      cur = newEntry(argStr, "foreign")
      hasCur = true

    of 1:
      flushEntry()
      cur = newEntry(argStr, "phrase")
      hasCur = true

    of 4:
      flushEntry()
      cur = newEntry(argStr, "nonstandard")
      hasCur = true

    of 0:
      flushChem()

      let t = argStr

      if t == "\n\n":
        flushSense()

      elif t.len > 0 and t[0].isDigit() and t[^1] == '.':
        flushSense()
        sense.number = t[0 .. ^2]

      elif t notin ["\n", " ", ": ", "; ", ""]:
        let clean = if t.startsWith("bentuk tidak baku: "): t[19..^1] else: t
        sense.text.add(clean)

    of 20:
      sense.pos = argStr
    of 21:
      sense.bahasa = argStr
    of 22:
      sense.bidang = argStr
    of 25:
      sense.ragam = argStr

    of 30:
      sense.markers.add("ki")
    of 31:
      sense.markers.add("sing")
    of 32:
      sense.markers.add("akr")
    of 33:
      sense.markers.add("ukp")

    of 10:
      xrefKind = "baku"
    of 12:
      xrefKind = "turunan"
    of 13:
      xrefKind = "lihat"
    of 14:
      xrefKind = "gabungan"
    of 15:
      xrefKind = "peribahasa"

    of 40:
      if xrefKind.len > 0:
        var found = false

        for g in sense.xrefGroups.mitems:
          if g.kind == xrefKind:
            g.refs.add(argNum)
            found = true
            break

        if not found:
          sense.xrefGroups.add(
            newXrefGroup(xrefKind, @[argNum])
          )

      else:
        sense.xrefs.add(argNum)

    of 41:
      sense.xrefs.add(argNum)

    of 2:
      sense.altForm = argStr
    of 42:
      sense.altText = argStr

    of 50:
      sense.examples.add(argStr)
    of 61:
      sense.link = argStr
    of 60:
      sense.abbrev = argStr

    of 23:
      sense.latin = argStr

    of 24:
      chemBuf.add(argStr)

    of 74:
      chemBuf.add(argStr)

    of 62:
      chemBuf.add(argStr)

    of 63:
      chemBuf.add(argStr)

    of 255:
      flushEntry()

    else:
      discard

  flushEntry()

  result = entries