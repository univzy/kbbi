import std/[dom, jsffi]
import ./[config, ffi]

var searchHistory*: seq[cstring] = @[]


proc setText*(id: cstring, html: cstring) =
  let el = getById(id)
  if not el.isNil: setInnerHTML(el, html)


proc setClass*(id: cstring, cls: cstring, add: bool) =
  let el = getById(id)
  if el.isNil: return
  if add: el.classList.add(cls) else: el.classList.remove(cls)


proc saveHistoryToStorage*() =
  if searchHistory.len == 0:
    localStorageSetItem(keySearchHistory, "")
    return
  var jsonStr: cstring = "["
  for i in 0 ..< searchHistory.len:
    let h = searchHistory[i]
    jsonStr = jsonStr & "\"" & jsStrEsc(h) & "\""
    if i < searchHistory.len - 1: jsonStr = jsonStr & ","
  jsonStr = jsonStr & "]"
  localStorageSetItem(keySearchHistory, jsonStr)


proc loadHistoryFromStorage*() {.exportc.} =
  let stored = localStorageGetItem(keySearchHistory)
  searchHistory = @[]
  if stored == "": return
  var items: JsObject
  {.emit: ["try { ", items, " = JSON.parse(", stored, "); } catch(e) { ", items, " = []; }"].}
  if not items.isNil:
    let len = jsLength(items)
    for i in 0 ..< len:
      let item = jsStr(jsItem(items, i))
      if item != "": searchHistory.add(item)


proc renderHistory*() =
  var html: cstring = ""
  for h in searchHistory:
    html = html & "<button class=\"hist-item\" data-action=\"search\" data-query=\"" & htmlEsc(h) & "\" role=\"listitem\">" & htmlEsc(h) & "</button>"
  setText("history-list", html)
  setClass("history-section", "hidden", searchHistory.len == 0)


proc updateHistory*(word: cstring) =
  let normWord = normalizeWord(word)
  var filtered: seq[cstring] = @[]
  for h in searchHistory:
    if normalizeWord(h) != normWord: filtered.add(h)
  searchHistory = filtered
  searchHistory.insert(word, 0)
  if searchHistory.len > maxHistory: searchHistory = searchHistory[0..maxHistory-1]
  saveHistoryToStorage()
  renderHistory()


proc clearHistory*() {.exportc.} =
  searchHistory = @[]
  saveHistoryToStorage()
  renderHistory()