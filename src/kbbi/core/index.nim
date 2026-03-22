import ./[types, varint]

proc parseOfflens*(data: seq[byte]): seq[OffLen] =
  var s = newVStream(data)
  let count = s.readVarint()
  if count <= 0:
    return
  result = newSeq[OffLen](count)
  var fileIdx = -1
  var running = 0
  for i in 0 ..< count:
    var delta = s.readVarint()
    if delta < 0:
      break
    if delta == 65535:
      fileIdx += 1
      delta = s.readVarint()
      if delta < 0:
        break
      running = 0
    result[i] = OffLen(fileIdx: fileIdx, offset: running)
    running += delta

proc parseNilai*(data: seq[byte]): seq[string] =
  var s = newVStream(data)
  let count = s.readVarint()
  if count <= 0:
    return
  result = newSeq[string](count)
  for i in 0 ..< count:
    let length = s.readUint8()
    if length <= 0:
      break
    result[i] = s.readRawString(length)

proc parseKatIndex*(data: seq[byte]): seq[Kategori] =
  var s = newVStream(data)
  let count = s.readVarint()
  if count <= 0:
    return
  result = newSeq[Kategori](count)
  for i in 0 ..< count:
    let nilai = s.readString()
    let desc = s.readString()
    if nilai.len == 0 or desc.len == 0:
      break
    result[i] = newKategori(nilai, desc)

proc parseKatFilter*(data: seq[byte]): seq[int] =
  var s = newVStream(data)
  let count = s.readVarint()
  if count <= 0:
    return
  result = newSeq[int](count)
  for i in 0 ..< count:
    let val = s.readVarint()
    if val < 0:
      break
    result[i] = val
