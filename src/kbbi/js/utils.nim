import karax/[kbase]

proc isValidString*(s: kstring): bool {.inline.} =
  s != "" and s != "null" and s != "undefined"
