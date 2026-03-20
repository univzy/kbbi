import std/[strutils]

proc fuzzyNorm*(s: string): string =
  for c in s:
    let cp = ord(c)
    if   cp >= ord('a') and cp <= ord('z'): result.add(c)
    elif cp >= ord('A') and cp <= ord('Z'): result.add(chr(cp + 32))
    elif cp >= ord('0') and cp <= ord('9'): result.add(c)
    elif cp > 127: result.add(c)

proc cleanLatin*(text: string): string =
  result = text
  for tag in ["<i>", "</i>", "<I>", "</I>", "&lt;i&gt;", "&lt;/i&gt;"]:
    result = result.replace(tag, "")