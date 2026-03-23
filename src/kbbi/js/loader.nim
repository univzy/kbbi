import std/jsffi except `&`
import std/[asyncjs]
import karax/[kbase, karax, kdom, jstrutils]
import ./[ffi, db, appstate]

proc setLoadStatus*(msg: kstring) =
  let el = document.getElementById("load-status")
  if not el.isNil:
    el.innerHTML = msg

proc hideOverlay*() =
  let el = document.getElementById("load-overlay")
  if not el.isNil:
    el.classList.add("hidden")

proc loadDatabase*() {.async.} =
  if dbLoading or not sqlDb.isNil:
    return
  dbLoading = true
  state.dbError = ""
  try:
    setLoadStatus("Memulai sql.js…")
    var sqlCfg: JsObject
    {.emit: "`sqlCfg` = {locateFile: function(f){return f;}}".}
    let SQL = await initSqlJs(sqlCfg)
    initWordCache()
    setLoadStatus("Mengunduh kbbi.db… (0%)")
    var resp: JsObject
    {.
      emit: """
      try {
        const CACHE_NAME = '`cacheKey`';
        const URL = 'kbbi.db';
        const loadBar = document.querySelector('.load-bar');
        const loadStatus = document.getElementById('load-status');
        const cache = await caches.open(CACHE_NAME);
        let response = await cache.match(URL);
        if (!response) {
          const fetched = await fetch(URL, { cache: 'no-store' });
          if (!fetched.ok) throw new Error('kbbi.db fetch failed: ' + fetched.status);
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
                const pct = Math.min(100, Math.round((loaded / total) * 100));
                if (loadBar) loadBar.style.width = pct + '%';
                if (loadStatus && pct !== 100) loadStatus.textContent = 'Mengunduh kbbi.db… (' + pct + '%)';
                if (loadStatus && pct === 100) loadStatus.textContent = 'Menginisialisasi database...';
              }
            } finally { reader.releaseLock(); }
            const blob = new Blob(chunks);
            response = new Response(blob);
          } else {
            response = fetched;
          }
          await cache.put(URL, response.clone());
        } else {
          if (loadBar) loadBar.style.width = '100%';
          if (loadStatus) loadStatus.textContent = 'Memuat dari cache… (100%)';
        }
        `resp` = response;
      } catch(e) {
        `resp` = await fetch('kbbi.db');
        const loadBar = document.querySelector('.load-bar');
        if (loadBar) loadBar.style.width = '100%';
      }
    """
    .}
    setLoadStatus("Membuka database…")
    let buf = await arrayBuffer(resp)
    let u8 = uint8Array(buf)
    sqlDb = newDb(SQL, u8)
    loadKategori()
    dbLoading = false
    state.isDbReady = true
    hideOverlay()
    redraw()
    let inp = document.getElementById("search-input")
    if not inp.isNil:
      inp.focus()
  except:
    dbLoading = false
    state.dbError = "Gagal memuat database. Periksa koneksi atau cache."
    setLoadStatus(
      kstring("⚠ ") & state.dbError &
        kstring(
          " <a href='javascript:location.reload()' style='color:var(--accent)'>Muat ulang</a>"
        )
    )
