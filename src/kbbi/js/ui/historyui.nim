import karax/[vdom, karax, karaxdsl, kdom]
import ../[history, actions]

proc renderHistorySection*(): VNode =
  if searchHistory.len == 0:
    return buildHtml(span())

  buildHtml(tdiv(id = "history-section")):
    tdiv(class = "history-header"):
      p(class = "hist-label", role = "heading", "aria-level" = "3"):
        text "Riwayat"
      button(
        id = "clear-history-btn",
        class = "clear-history-btn",
        title = "Hapus semua riwayat pencarian",
        "aria-label" = "Hapus riwayat",
      ):
        proc onclick(ev: Event, n: VNode) =
          clearHistory()
          redraw()

        span:
          text "✕"
    tdiv(
      id = "history-list", role = "list", "aria-label" = "Riwayat pencarian terakhir"
    ):
      for h in searchHistory:
        button(
          class = "hist-item",
          role = "listitem",
          "data-action" = "search",
          "data-query" = h,
        ):
          proc onclick(ev: Event, n: VNode) =
            nimSearch(h)

          text h
