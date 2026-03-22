type VStream* = ref object
  data*: seq[byte]
  pos*: int

const CODE_ARG*: array[256, int] = block:
  var a: array[256, int]
  for c in [0, 1, 2, 3, 4, 5]:
    a[c] = 3
  for c in [10, 11, 12, 13, 14, 15]:
    a[c] = 1
  for c in [20, 21, 22, 23, 24, 25]:
    a[c] = 3
  for c in [30, 31, 32, 33]:
    a[c] = 1
  a[40] = 2
  a[41] = 2
  a[42] = 3
  a[50] = 3
  for c in [60, 61, 62, 63]:
    a[c] = 3
  a[74] = 3
  a[255] = 1
  a

func atEnd*(s: VStream): bool =
  s.pos >= s.data.len

func readByte*(s: var VStream): int =
  if s.atEnd():
    return -1
  result = s.data[s.pos].int
  s.pos += 1

func readVarint*(s: var VStream): int =
  let v = s.readByte()
  if v < 0:
    return -1
  if v < 240:
    return v
  case v
  of 254:
    let b = s.readByte()
    return if b < 0: -1 else: b
  of 253:
    let b = s.readByte()
    return
      if b < 0:
        -1
      else:
        (b or 256)
  of 252:
    let b1 = s.readByte()
    let b2 = s.readByte()
    if b1 < 0 or b2 < 0:
      return -1
    return (b1 shl 8) or b2
  of 251:
    let b1 = s.readByte()
    let b2 = s.readByte()
    if b1 < 0 or b2 < 0:
      return -1
    return (b1 shl 8) or 65536 or b2
  of 250:
    let b1 = s.readByte()
    let b2 = s.readByte()
    let b3 = s.readByte()
    if b1 < 0 or b2 < 0 or b3 < 0:
      return -1
    return (b1 shl 16) or (b2 shl 8) or b3
  else:
    return -1

func readRawString*(s: var VStream, length: int): string =
  if length <= 0:
    return ""
  let endPos = s.pos + length
  if endPos > s.data.len:
    return ""
  result = cast[string](s.data[s.pos ..< endPos])
  s.pos = endPos

func readString*(s: var VStream): string =
  let n = s.readVarint()
  if n <= 0:
    return ""
  s.readRawString(n)

func readUint8*(s: var VStream): int =
  s.readByte()

func newVStream*(data: seq[byte]): VStream =
  let s = new(VStream)
  s.data = data
  s.pos = 0
  s

func newVStream*(data: string): VStream =
  let s = new(VStream)
  s.data = cast[seq[byte]](data)
  s.pos = 0
  s
