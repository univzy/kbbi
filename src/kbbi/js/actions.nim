import karax/[kbase, karax, jstrutils, kdom]
import ./[types, modes, appstate, ffi, db, history, search]

proc doSearchWith*(query: kstring, mode: SearchMode) =
  if not state.isDbReady:
    state.resultHtml = dbLoadingError
    state.hasResult = true
    state.isLoading = false
    redraw()
    return
  if query != "" and not isListMode(mode):
    updateHistory(query)
  var res: SearchResult
  try:
    case mode
    of ModeFts:
      res = searchFTS(query)
    of ModePrefix:
      res = searchPrefix(query)
    of ModeKatKelas:
      res = searchKat("kelas", state.katFilter, query)
    of ModeKatBahasa:
      res = searchKat("bahasa", state.katFilter, query)
    of ModeKatBidang:
      res = searchKat("bidang", state.katFilter, query)
    of ModeKatRagam:
      res = searchKat("ragam", state.katFilter, query)
    of ModeListKelas:
      res = searchList("kelas")
    of ModeListBahasa:
      res = searchList("bahasa")
    of ModeListBidang:
      res = searchList("bidang")
    of ModeListRagam:
      res = searchList("ragam")
    else:
      res = searchExact(query)
      if not res.found:
        res = searchPrefix(query)
  except:
    let errMsg = getCurrentExceptionMsg()
    {.emit: "console.error('KBBI search error:', `errMsg`, new Error().stack);".}
    res = SearchResult(
      html: "<div class=\"error\"><p>Kesalahan saat mencari. Coba lagi.</p></div>",
      found: false,
      word: "",
      error: SearchException,
    )
  state.resultHtml = res.html
  state.hasResult = true
  state.isLoading = false
  redraw()
  requestAnimationFrame(
    proc() =
      requestAnimationFrame(
        proc() =
          let resEl = document.getElementById("result")
          if not resEl.isNil:
            smoothScroll(resEl)
      )
  )

proc doSearch*() =
  let q = state.query.strip()
  if q == "" and not isListMode(state.mode):
    let el = document.getElementById("search-input")
    if not el.isNil:
      el.classList.remove("glitch")
      {.emit: "void `el`.offsetWidth;".}
      el.classList.add("glitch")
      discard setTimeout(
        proc() =
          let inp = document.getElementById("search-input")
          if not inp.isNil:
            inp.classList.remove("glitch")
            inp.focus()
        ,
        400,
      )
    return
  state.isLoading = true
  redraw()
  doSearchWith(q, state.mode)

proc nimSearch*(word: kstring) {.exportc.} =
  state.query = word
  state.mode = ModeAuto
  state.katFilter = ""
  state.isLoading = true
  redraw()
  doSearchWith(word, ModeAuto)

proc nimSearchById*(id: kstring) {.exportc.} =
  state.isLoading = false
  let res = searchById(id)
  if res.word != "":
    state.query = res.word
    updateHistory(res.word)
  state.resultHtml = res.html
  state.hasResult = true
  redraw()
  requestAnimationFrame(
    proc() =
      requestAnimationFrame(
        proc() =
          let resEl = document.getElementById("result")
          if not resEl.isNil:
            smoothScroll(resEl)
      )
  )

proc nimKat*(jenis, nilai: kstring) {.exportc.} =
  state.katFilter = nilai
  case $jenis
  of "kelas":
    state.mode = ModeKatKelas
  of "bahasa":
    state.mode = ModeKatBahasa
  of "bidang":
    state.mode = ModeKatBidang
  of "ragam":
    state.mode = ModeKatRagam
  else:
    discard
  state.query = ""
  state.isLoading = true
  redraw()
  let res = searchKat(jenis, nilai, "")
  state.resultHtml = res.html
  state.hasResult = true
  state.isLoading = false
  redraw()
  requestAnimationFrame(
    proc() =
      requestAnimationFrame(
        proc() =
          let resElKat = document.getElementById("result")
          if not resElKat.isNil:
            smoothScroll(resElKat)
      )
  )

proc handleResultClick*(ev: Event) =
  let target = cast[kdom.Element](ev.target)
  if target.isNil:
    return
  let action = target.getAttribute("data-action")
  if action == "search":
    let q = target.getAttribute("data-query")
    if q != "":
      nimSearch(q)
  elif action == "search-id":
    let id = target.getAttribute("data-id")
    if id != "":
      nimSearchById(id)
  elif action == "filter-kat":
    let jenis = target.getAttribute("data-jenis")
    let nilai = target.getAttribute("data-nilai")
    if jenis != "" and nilai != "":
      nimKat(jenis, nilai)
