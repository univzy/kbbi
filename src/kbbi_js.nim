import karax/[kbase, vdom, karaxdsl, karax, kdom]
import kbbi/js/[types, modes, appstate, ffi, actions, loader, history]
import kbbi/js/ui/[dropdown, overlay, historyui, hints]
export renderModeHints # compact: registered in vcomponents, used via karaxdsl

proc setupGlobalListeners() =
  document.body.addEventListener(
    "click",
    proc(ev: Event) =
      if state.dropdownOpen:
        let target = cast[kdom.Element](ev.target)
        let inside = target.closest(".cp-select")
        if inside.isNil:
          state.dropdownOpen = false
          redraw()
    ,
  )
  setGlobalCpSelect(pickModeByString)

proc createDom(): VNode =
  buildHtml(tdiv(id = "karax-root")):
    renderLoadOverlay()

    tdiv(class = "top-bar")

    tdiv(class = "page"):
      header(class = "hero"):
        h1(class = "hero-kicker"):
          text "Kamus Besar Bahasa Indonesia"
        h2:
          text "Temukan "
          em("data-text" = "makna"):
            text "makna"
          br()
          text "setiap kata"
        h3(class = "hero-sub"):
          text "Data resmi Kemendikdasmen · Ringan · Bekerja offline"

      tdiv(class = "search-area"):
        tdiv(class = "search-row"):
          label(`for` = "search-input", class = "visually-hidden"):
            text "Cari kata dalam KBBI"

          input(
            `type` = "text",
            id = "search-input",
            placeholder = "Ketik sebuah kata…",
            autocomplete = "off",
            autocorrect = "off",
            autocapitalize = "none",
            spellcheck = "false",
            title = "Ketik satu kata untuk mencari. Tekan Enter atau klik tombol Cari.",
            value = state.query,
          ):
            proc oninput(ev: Event, n: VNode) =
              let el = cast[kdom.Element](ev.target)
              state.query = el.value

            proc onkeydown(ev: Event, n: VNode) =
              let kev = cast[KeyboardEvent](ev)
              if kev.keyCode == 13 or kev.key == "Enter":
                doSearch()

          tdiv(class = "search-divider")
          renderDropdown()

          button(
            id = "search-btn",
            class = if state.isLoading: "loading" else: "",
            title = "Klik untuk mencari (atau tekan Enter)",
            "aria-label" = "Tombol pencarian",
          ):
            proc onclick(ev: Event, n: VNode) =
              doSearch()

            tdiv(
              id = "spinner",
              class =
                (if state.isLoading: kstring("spinner")
                else: kstring("spinner hidden")),
            )
            span(id = "btn-text"):
              text if state.isLoading: "Mencari..." else: "Cari"

        if isKatMode(state.mode):
          tdiv(id = "kat-filter-row", class = "kat-filter-row"):
            span(id = "kat-filter-label", class = "kat-filter-label"):
              text katFilterLabel(state.mode)
            input(
              `type` = "text",
              id = "kat-filter-input",
              placeholder = "mis. Jw, n, Dok, cak…",
              autocomplete = "off",
              autocorrect = "off",
              autocapitalize = "none",
              spellcheck = "false",
              title =
                "Masukkan kode kategori untuk memfilter hasil. Contoh: n (nomina), Jw (Jawa), Dok (Dokumen).",
              value = state.katFilter,
            ):
              proc oninput(ev: Event, n: VNode) =
                let el = cast[kdom.Element](ev.target)
                state.katFilter = el.value

              proc onkeydown(ev: Event, n: VNode) =
                let kev = cast[KeyboardEvent](ev)
                if kev.keyCode == 13 or kev.key == "Enter":
                  doSearch()

        renderModeHints()
        renderHistorySection()

      tdiv(
        id = "result",
        class = if state.hasResult: "" else: "hidden",
        "aria-live" = "polite",
        "aria-label" = "Hasil pencarian",
      ):
        proc onclick(ev: Event, n: VNode) =
          handleResultClick(ev)

        if state.hasResult:
          tdiv(class = "result-inner"):
            verbatim state.resultHtml

      footer:
        tdiv:
          span(class = "nim-badge"):
            span(class = "nim-dot")
            text "Logic: Nim → kbbi.js"
          text "\u2002"
          span(class = "nim-badge"):
            span(class = "sqljs-dot")
            text "Data: kbbi.db → sql.js wasm"
        tdiv:
          text "Data resmi KBBI · Source: "
          a(
            href = "https://github.com/univzy/kbbi",
            target = "_blank",
            class = "kbbi-link",
          ):
            text "kbbi.nim"
          text " · "
          a(href = "https://nim-lang.org", target = "_blank", class = "nim-link"):
            text "nim-lang.org"
          text " · "
          a(
            href = "https://github.com/sql-js/sql.js",
            target = "_blank",
            class = "sqljs-link",
          ):
            text "sql.js"

proc main() =
  loadHistoryFromStorage()
  setupGlobalListeners()
  setRenderer createDom
  discard loadDatabase()

main()
