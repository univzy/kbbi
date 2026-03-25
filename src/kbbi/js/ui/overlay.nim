import karax/[vdom, karaxdsl, jstrutils]
import ../appstate

proc renderLoadOverlay*(): VNode =
  buildHtml(tdiv(id = "load-overlay", class = if state.isDbReady: "hidden" else: "")):
    tdiv(class = "load-logo", "data-text" = "re:KBBI"):
      span(class = "re"):
        text "re"
      span(class = "kbbi"):
        text ":KBBI"
    tdiv(class = "load-bar-wrap"):
      tdiv(class = "load-bar")
    tdiv(id = "load-status"):
      if state.dbError != "":
        text "⚠ " & state.dbError & " "
        a(href = "javascript:location.reload()", class = "load-err-reload"):
          text "Muat ulang"
      else:
        text "Memulai…"