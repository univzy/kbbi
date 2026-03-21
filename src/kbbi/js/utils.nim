proc isValidString*(s: cstring): bool {.inline.} =
  s != "" and s != "null" and s != "undefined"