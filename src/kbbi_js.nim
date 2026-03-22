import std/[dom, jsffi, asyncjs, strutils]
import kbbi/js/[config, ffi, db, history, search]

proc getKatFilter(): cstring =
  let el = getById("kat-filter-input")
  if el.isNil:
    return ""
  return cstring(($getValue(el)).strip())

proc updateKatFilterRow*(mode: cstring) =
  let row = getById("kat-filter-row")
  let lbl = getById("kat-filter-label")
  if row.isNil or lbl.isNil:
    return
  let modeStr = $mode
  if modeStr.startsWith("kat-"):
    let jenis = modeStr[4 ..^ 1]
    let labelText: cstring =
      case jenis
      of "kelas":
        "kelas kata"
      of "bahasa":
        "bahasa"
      of "bidang":
        "bidang"
      of "ragam":
        "ragam"
      else:
        cstring(jenis)
    setInnerHTML(lbl, labelText)
    row.classList.remove("hidden")
    let filterInp = getById("kat-filter-input")
    if not filterInp.isNil:
      focusEl(filterInp)
  else:
    row.classList.add("hidden")

proc getMode(): cstring =
  let sel = getById("search-mode")
  if sel.isNil:
    return "auto"
  return getValue(sel)

proc setText(id: cstring, html: cstring) =
  let el = getById(id)
  if not el.isNil:
    setInnerHTML(el, html)

proc setClass(id: cstring, cls: cstring, add: bool) =
  let el = getById(id)
  if el.isNil:
    return
  if add:
    el.classList.add(cls)
  else:
    el.classList.remove(cls)

proc doSearchWith*(query: cstring, mode: cstring) =
  if sqlDb.isNil:
    setText("result", dbLoadingError)
    setClass("result", "hidden", false)
    return
  setLoading(false)
  let res = getById("result")
  if res.isNil:
    return
  if query != "" and not ($mode).startsWith("list-"):
    updateHistory(query)
  var result: SearchResult
  try:
    case $mode
    of "fts":
      result = searchFTS(query)
    of "prefix":
      result = searchPrefix(query)
    of "kat-kelas":
      result = searchKat("kelas", getKatFilter(), query)
    of "kat-bahasa":
      result = searchKat("bahasa", getKatFilter(), query)
    of "kat-bidang":
      result = searchKat("bidang", getKatFilter(), query)
    of "kat-ragam":
      result = searchKat("ragam", getKatFilter(), query)
    of "list-kelas":
      result = searchList("kelas")
    of "list-bahasa":
      result = searchList("bahasa")
    of "list-bidang":
      result = searchList("bidang")
    of "list-ragam":
      result = searchList("ragam")
    else:
      result = searchExact(query)
      if not result.found:
        result = searchPrefix(query)
  except:
    result = SearchResult(
      html: "<div class=\"error\"><p>Kesalahan saat mencari. Coba lagi.</p></div>",
      found: false,
      word: "",
      error: SearchException,
    )
  setInnerHTML(res, result.html)
  res.classList.remove("hidden")
  smoothScroll(res)

proc doSearch*() {.exportc.} =
  let mode = getMode()
  let inp = getById("search-input")
  if inp.isNil:
    return
  let v = cstring(($getValue(inp)).strip())
  if v == "" and not ($mode).startsWith("list-"):
    return
  setLoading(true)
  doSearchWith(v, mode)

proc nimSearch*(word: cstring) {.exportc.} =
  let inp = getById("search-input")
  if not inp.isNil:
    setValue(inp, word)
  let sel = getById("search-mode")
  if not sel.isNil:
    setValue(sel, "auto")
  updateKatFilterRow("auto")
  setLoading(true)
  doSearchWith(word, "auto")

proc nimSearchById*(id: cstring) {.exportc.} =
  setLoading(false)
  let res = getById("result")
  if res.isNil:
    return
  let result = searchById(id)
  if result.word != "":
    let inp = getById("search-input")
    if not inp.isNil:
      setValue(inp, result.word)
    updateHistory(result.word)
  setInnerHTML(res, result.html)
  res.classList.remove("hidden")
  smoothScroll(res)

proc nimKat*(jenis, nilai: cstring) {.exportc.} =
  let mode: cstring = "kat-" & jenis
  let sel = getById("search-mode")
  if not sel.isNil:
    setValue(sel, mode)
  updateKatFilterRow(mode)
  let katInp = getById("kat-filter-input")
  if not katInp.isNil:
    setValue(katInp, nilai)
  let inp = getById("search-input")
  if not inp.isNil:
    setValue(inp, "")
  let res = getById("result")
  if res.isNil:
    return
  if sqlDb.isNil:
    setText("result", dbLoadingError)
    setClass("result", "hidden", false)
    return
  let result = searchKat(jenis, nilai, "")
  setInnerHTML(res, result.html)
  res.classList.remove("hidden")
  smoothScroll(res)

proc handleResultClick(e: Event) =
  let target = cast[Element](e.target)
  if target.isNil:
    return
  let action = target.getAttribute("data-action")
  if action == "search".cstring:
    let query = target.getAttribute("data-query")
    if query != "":
      nimSearch(query)
  elif action == "search-id".cstring:
    let id = target.getAttribute("data-id")
    if id != "":
      nimSearchById(id)
  elif action == "filter-kat".cstring:
    let jenis = target.getAttribute("data-jenis")
    let nilai = target.getAttribute("data-nilai")
    if jenis != "" and nilai != "":
      nimKat(jenis, nilai)

proc initCustomDropdown() =
  let cpSelect = getById("cp-select")
  let panel = getById("cp-select-panel")
  let labelEl = getById("cp-select-label")
  let nativeEl = getById("search-mode")
  if cpSelect.isNil or panel.isNil or labelEl.isNil or nativeEl.isNil:
    return
  if getAttribute(cpSelect, "data-cp-initialized") == "true":
    return
  setAttribute(cpSelect, "data-cp-initialized", "true")

  let nodeList = querySelectorAll(panel, ".cp-select__option")
  var allOpts: seq[Element] = @[]
  let optCount = jsLength(nodeList)
  for i in 0 ..< optCount:
    allOpts.add(cast[Element](jsItem(nodeList, i)))

  var labelMap: JsObject
  {.
    emit: [
      labelMap,
      """ = {
    'auto':        'Otomatis',
    'prefix':      'Awalan',
    'fts':         'Teks penuh',
    'kat-kelas':   'Kelas kata',
    'kat-bahasa':  'Bahasa',
    'kat-bidang':  'Bidang',
    'kat-ragam':   'Ragam',
    'list-kelas':  'Daftar kelas',
    'list-bahasa': 'Daftar bahasa',
    'list-bidang': 'Daftar bidang',
    'list-ragam':  'Daftar ragam'
  };""",
    ]
  .}

  proc labelFor(value: cstring): cstring =
    var lbl: cstring = ""
    {.emit: [lbl, " = ", labelMap, "[String(", value, ")] || String(", value, ");"].}
    return lbl

  var highlightedIdx = 0
  var selectedIdx = 0

  proc setHighlight(idx: int, scroll: bool) =
    let clamped = max(0, min(idx, allOpts.len - 1))
    highlightedIdx = clamped
    for i in 0 ..< allOpts.len:
      let o = allOpts[i]
      let oClassList = o.classList
      if i == clamped:
        oClassList.add("cp-opt--highlighted")
      else:
        oClassList.remove("cp-opt--highlighted")
    if scroll:
      scrollIntoViewNearest(allOpts[clamped])

  proc closePanel() =
    let cpSelectClassList = cpSelect.classList
    cpSelectClassList.remove("is-open")
    setAttribute(cpSelect, "aria-expanded", "false")
    for i in 0 ..< allOpts.len:
      allOpts[i].classList.remove("cp-opt--highlighted")

  proc openPanel() =
    let cpSelectClassList = cpSelect.classList
    cpSelectClassList.add("is-open")
    setAttribute(cpSelect, "aria-expanded", "true")
    setHighlight(selectedIdx, true)

  proc pick(value: cstring) =
    var idx = -1
    for i in 0 ..< allOpts.len:
      if dataValue(allOpts[i]) == value:
        idx = i
        break
    selectedIdx = if idx >= 0: idx else: 0
    for i in 0 ..< allOpts.len:
      let o = allOpts[i]
      let oClassList = o.classList
      if i == selectedIdx:
        oClassList.add("cp-select__option--selected")
      else:
        oClassList.remove("cp-select__option--selected")
    elTextContent(labelEl, labelFor(value))
    setValue(nativeEl, value)
    dispatchChange(nativeEl)
    closePanel()

  addClickListener(
    cpSelect,
    proc(ev: Event) =
      let opt = closestOpt(cast[Element](ev.target))
      if not opt.isNil:
        let v = dataValue(opt)
        pick(v)
        return
      if cpSelect.classList.contains("is-open"):
        closePanel()
      else:
        openPanel(),
  )

  addClickListener(
    document.body,
    proc(ev: Event) =
      if not contains(cpSelect, cast[Element](ev.target)):
        closePanel()
    ,
  )

  addKbListener(
    cpSelect,
    proc(ev: KeyboardEvent) =
      let isOpen = cpSelect.classList.contains("is-open")
      let key = ev.key
      if key == "Escape":
        ev.preventDefault()
        closePanel()
      elif key == "Enter" or key == " ":
        ev.preventDefault()
        if not isOpen:
          openPanel()
        else:
          pick(dataValue(allOpts[highlightedIdx]))
      elif key == "ArrowDown":
        ev.preventDefault()
        if not isOpen:
          openPanel()
        else:
          setHighlight(highlightedIdx + 1, true)
      elif key == "ArrowUp":
        ev.preventDefault()
        if not isOpen:
          openPanel()
        else:
          setHighlight(highlightedIdx - 1, true),
  )

  setGlobalCpSelect(pick)

proc loadDatabase() {.async.} =
  if dbLoading or not sqlDb.isNil:
    return
  dbLoading = true
  setText("load-status", "Memulai sql.js…")
  setClass("load-overlay", "hidden", false)
  dbLoadError = ""
  try:
    var sqlCfg: JsObject
    {.
      emit: [
        sqlCfg,
        " = {locateFile: function(f){return 'https://cdn.jsdelivr.net/npm/sql.js-fts5@1.4.0/dist/' + f;}}",
      ]
    .}
    let SQL = await initSqlJs(sqlCfg)
    initWordCache()
    setText("load-status", "Mengunduh kbbi.db… (0%)")
    var resp: JsObject
    {.
      emit: [
        """
      try {
        const CACHE_NAME = '""", cacheKey,
        """';
        const URL = 'kbbi.db';
        const loadBar = document.querySelector('.load-bar');
        const loadStatus = document.getElementById('load-status');

        const cache = await caches.open(CACHE_NAME);
        let response = await cache.match(URL);
        let fromCache = !!response;

        if (!response) {
          const fetched = await fetch(URL, { cache: 'no-store' });
          if (!fetched.ok) {
            throw new Error('kbbi.db fetch failed: ' + fetched.status);
          }

          // Track download progress
          const contentLength = fetched.headers.get('content-length');
          if (contentLength) {
            const total = parseInt(contentLength, 10);
            const reader = fetched.body.getReader();
            let loaded = 0;
            const chunks = [];

            try {
              while (true) {
                const {done, value} = await reader.read();
                if (done) break;
                chunks.push(value);
                loaded += value.length;
                const percent = Math.min(100, Math.round((loaded / total) * 100));
                if (loadBar) loadBar.style.width = percent + '%';
                if (loadStatus && percent !== 100) loadStatus.textContent = 'Mengunduh kbbi.db… (' + percent + '%)';
                if (loadStatus && percent === 100) loadStatus.textContent = 'Menginisialisasi database...';
              }
            } finally {
              reader.releaseLock();
            }

            // Reconstruct response from chunks
            const blob = new Blob(chunks);
            response = new Response(blob);
          } else {
            response = fetched;
          }

          // Cache the downloaded file
          await cache.put(URL, response.clone());
        } else {
          // Loaded from cache — show 100%
          if (loadBar) loadBar.style.width = '100%';
          if (loadStatus) loadStatus.textContent = 'Memuat dari cache… (100%)';
        }

        """,
        resp,
        """ = response;
      } catch (e) {
        // Fallback fetch without progress tracking
        """,
        resp,
        """ = await fetch('kbbi.db');
        const loadBar = document.querySelector('.load-bar');
        if (loadBar) loadBar.style.width = '100%';
      }
    """,
      ]
    .}
    let buf = await arrayBuffer(resp)
    let u8 = uint8Array(buf)
    setText("load-status", "Membuka database…")
    sqlDb = newDb(SQL, u8)
    loadKategori()
    setClass("load-overlay", "hidden", true)
    let inp = getById("search-input")
    if not inp.isNil:
      focusEl(inp)
    dbLoading = false
  except:
    dbLoading = false
    dbLoadError = "Gagal memuat database"
    setText(
      "load-status",
      "⚠ Gagal memuat. Periksa koneksi atau cache. <a href='javascript:location.reload()' style='color:var(--accent)'>Muat ulang</a>",
    )

window.onload = proc(e: Event) =
  let inp = getById("search-input")
  let btn = getById("search-btn")
  let sel = getById("search-mode")
  let katInp = getById("kat-filter-input")
  let res = getById("result")

  loadHistoryFromStorage()
  renderHistory()
  initCustomDropdown()

  if not inp.isNil:
    addKbListener(
      inp,
      proc(ev: KeyboardEvent) =
        if ev.keyCode == 13 or ev.key == "Enter":
          doSearch()
      ,
    )
  if not katInp.isNil:
    addKbListener(
      katInp,
      proc(ev: KeyboardEvent) =
        if ev.keyCode == 13 or ev.key == "Enter":
          doSearch()
      ,
    )
  if not btn.isNil:
    addClickListener(
      btn,
      proc(ev: Event) =
        doSearch(),
    )
  if not sel.isNil:
    addChangeListener(
      sel,
      proc(ev: Event) =
        updateKatFilterRow(getMode()),
    )

  if not res.isNil:
    addClickListener(res, handleResultClick)

  let clearBtn = getById("clear-history-btn")
  if not clearBtn.isNil:
    addClickListener(
      clearBtn,
      proc(ev: Event) =
        clearHistory(),
    )

  let histList = getById("history-list")
  if not histList.isNil:
    addClickListener(histList, handleResultClick)

  discard loadDatabase()
