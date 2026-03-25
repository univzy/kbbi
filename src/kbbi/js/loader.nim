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
    var dbBytes: JsObject
    {.
      emit: """
      const GZ_URL  = 'https://huggingface.co/datasets/univzy/kbbi/resolve/main/kbbi.db.gz';
      const RAW_URL = 'https://huggingface.co/datasets/univzy/kbbi/resolve/main/kbbi.db';
      const loadBar    = document.querySelector('.load-bar');
      const loadStatus = document.getElementById('load-status');

      const useGzip   = typeof DecompressionStream !== 'undefined';
      const URL       = useGzip ? GZ_URL : RAW_URL;
      const CACHE_KEY = useGzip ? '`cacheKey`_gz' : '`cacheKey`_raw';

      try {
        const cache = await caches.open('`cacheKey`');
        let cached = await cache.match(CACHE_KEY);
        if (cached) {
          if (loadBar)    loadBar.style.width = '100%';
          if (loadStatus) loadStatus.textContent = 'Memuat dari cache… (100%)';
          `dbBytes` = new Uint8Array(await cached.arrayBuffer());
        } else {
          const fetched = await fetch(URL, { cache: 'no-store' });
          if (!fetched.ok) throw new Error('fetch failed: ' + fetched.status);

          const contentLength = fetched.headers.get('content-length');
          const total = contentLength ? parseInt(contentLength, 10) : 0;

          let loaded = 0;
          const progressTransform = new TransformStream({
            transform(chunk, controller) {
              loaded += chunk.byteLength;
              if (total > 0) {
                const pct = Math.min(100, Math.round((loaded / total) * 100));
                if (loadBar) loadBar.style.width = pct + '%';
                if (loadStatus && pct !== 100) loadStatus.textContent = 'Mengunduh kbbi.db… (' + pct + '%)';
                if (loadStatus && pct === 100) loadStatus.textContent = 'Menginisialisasi database…';
              }
              controller.enqueue(chunk);
            }
          });

          let readable = fetched.body.pipeThrough(progressTransform);
          if (useGzip) readable = readable.pipeThrough(new DecompressionStream('gzip'));

          const reader = readable.getReader();
          const chunks = [];
          let decompressedBytes = 0;
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            chunks.push(value);
            decompressedBytes += value.byteLength;
            if (loaded >= total && total > 0 && useGzip) {
              const mb = (decompressedBytes / 1024 / 1024).toFixed(1);
              if (loadStatus) loadStatus.textContent = 'Mengekstrak… ' + mb + ' MB';
            }
          }

          if (loadStatus) loadStatus.textContent = 'Menyimpan ke cache…';
          const result = new Uint8Array(decompressedBytes);
          let offset = 0;
          for (const c of chunks) { result.set(c, offset); offset += c.byteLength; }

          `dbBytes` = result;
          try {
            await cache.put(CACHE_KEY, new Response(result.buffer));
          } catch (cacheErr) {
            console.warn('[kbbi] failed to cache database:', cacheErr);
          }
        }
      } catch(e) {
        console.error('[kbbi] loader error:', e);
        const r = await fetch(RAW_URL);
        `dbBytes` = new Uint8Array(await r.arrayBuffer());
        if (loadBar) loadBar.style.width = '100%';
      }
    """
    .}
    setLoadStatus("Membuka database…")
    sqlDb = newDb(SQL, dbBytes)
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
