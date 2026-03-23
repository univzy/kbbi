import karax/[kbase, jjson, jstrutils, localstorage]
import ./[config, ffi]

var searchHistory*: seq[kstring] = @[]

proc saveHistoryToStorage*() =
  if searchHistory.len == 0:
    setItem(keySearchHistory, "")
    return
  var jsonStr: kstring = "["
  for i in 0 ..< searchHistory.len:
    jsonStr = jsonStr & "\"" & jsStrEsc(searchHistory[i]) & "\""
    if i < searchHistory.len - 1:
      jsonStr = jsonStr & ","
  setItem(keySearchHistory, jsonStr & "]")

proc loadHistoryFromStorage*() =
  let stored = getItem(keySearchHistory)
  searchHistory = @[]
  if stored == nil or stored == "":
    return
  let items = parse(stored)
  if items.isNil:
    return
  for item in items:
    let s = item.getStr()
    if s != "":
      searchHistory.add(s)

proc updateHistory*(word: kstring) =
  let normWord = normalizeWord(word)
  var filtered: seq[kstring] = @[]
  for h in searchHistory:
    if normalizeWord(h) != normWord:
      filtered.add(h)
  searchHistory = filtered
  searchHistory.insert(word, 0)
  if searchHistory.len > maxHistory:
    searchHistory = searchHistory[0 .. maxHistory - 1]
  saveHistoryToStorage()

proc clearHistory*() =
  searchHistory = @[]
  saveHistoryToStorage()
