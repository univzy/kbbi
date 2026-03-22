import std/[strutils]
import pkg/[zippy]

type Salsa20 = array[16, uint32]

const key: array[32, byte] = block:
  const keyHex =
    "ffef8a8d11f535b73cd24fd31e" & "f296d0573ade68b1" & "f079cbdea460149e" & "d4036e"
  var a: array[32, byte]
  for i in 0 ..< 32:
    a[i] = byte(parseHexInt(keyHex[i * 2 ..< i * 2 + 2]))
  a

const nonce: array[8, byte] = block:
  const nonceHex = "fa1f5b7694c268fc"
  var a: array[8, byte]
  for i in 0 ..< 8:
    a[i] = byte(parseHexInt(nonceHex[i * 2 ..< i * 2 + 2]))
  a

const sigma: array[16, byte] = block:
  var a: array[16, byte]
  for i, c in "expand 32-byte k":
    a[i] = byte(c)
  a

proc `<<<`(x: uint32, y: SomeInteger): uint32 {.inline.} =
  (x shl y) or (x shr (32 - y))

proc quarterRound(a, b, c, d: var uint32) {.inline.} =
  b = b xor ((a + d) <<< 7)
  c = c xor ((b + a) <<< 9)
  d = d xor ((c + b) <<< 13)
  a = a xor ((d + c) <<< 18)

proc rowRound(x: var Salsa20) {.inline.} =
  quarterRound(x[0], x[1], x[2], x[3])
  quarterRound(x[5], x[6], x[7], x[4])
  quarterRound(x[10], x[11], x[8], x[9])
  quarterRound(x[15], x[12], x[13], x[14])

proc columnRound(x: var Salsa20) {.inline.} =
  quarterRound(x[0], x[4], x[8], x[12])
  quarterRound(x[5], x[9], x[13], x[1])
  quarterRound(x[10], x[14], x[2], x[6])
  quarterRound(x[15], x[3], x[7], x[11])

proc salsaHash(x: Salsa20): Salsa20 =
  var y: Salsa20 = x
  for i in 1 .. 10:
    columnRound(y)
    rowRound(y)
  for i in 0 ..< 16:
    y[i] += x[i]
  result = y

func leLoad32(b: openArray[byte], i: int): uint32 {.inline.} =
  uint32(b[i]) or (uint32(b[i + 1]) shl 8) or (uint32(b[i + 2]) shl 16) or
    (uint32(b[i + 3]) shl 24)

proc decryptFile*(path: string): seq[byte] =
  let enc = cast[seq[byte]](readFile(path))

  if enc.len > 0x10000000000000:
    raise
      newException(ValueError, "File too large for Salsa20 decryption (max 2^70 bytes)")

  var state: Salsa20
  state[0] = leLoad32(sigma, 0)
  state[1] = leLoad32(key, 0)
  state[2] = leLoad32(key, 4)
  state[3] = leLoad32(key, 8)
  state[4] = leLoad32(key, 12)
  state[5] = leLoad32(sigma, 4)
  state[6] = leLoad32(nonce, 0)
  state[7] = leLoad32(nonce, 4)
  state[8] = 0'u32
  state[9] = 0'u32
  state[10] = leLoad32(sigma, 8)
  state[11] = leLoad32(key, 16)
  state[12] = leLoad32(key, 20)
  state[13] = leLoad32(key, 24)
  state[14] = leLoad32(key, 28)
  state[15] = leLoad32(sigma, 12)
  var dec = newSeq[byte](enc.len)
  var pos = 0
  while pos < enc.len:
    var x = salsaHash(state)
    var ks: array[64, byte]
    for i in 0 .. 15:
      let v = x[i]
      ks[i * 4 + 0] = byte(v and 0xff)
      ks[i * 4 + 1] = byte((v shr 8) and 0xff)
      ks[i * 4 + 2] = byte((v shr 16) and 0xff)
      ks[i * 4 + 3] = byte((v shr 24) and 0xff)
    let chunk = min(64, enc.len - pos)
    for i in 0 ..< chunk:
      dec[pos + i] = enc[pos + i] xor ks[i]
    pos += 64
    state[8] += 1
    if state[8] == 0:
      state[9] += 1
      if state[9] == 0:
        raise newException(ValueError, "Salsa20 counter overflow - file too large")
  try:
    result = cast[seq[byte]](uncompress(cast[string](dec), dfGzip))
  except Exception as e:
    raise newException(ValueError, "Gzip decompression failed: " & e.msg)
