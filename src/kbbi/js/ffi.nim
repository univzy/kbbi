import std/jsffi except `&`
import std/[asyncjs]
import karax/[kbase, kdom, jstrutils]

proc arrayBuffer*(resp: JsObject): Future[JsObject] {.importcpp: "#.arrayBuffer()".}

proc uint8Array*(buf: JsObject): JsObject {.importcpp: "new Uint8Array(#)".}

proc initSqlJs*(cfg: JsObject): Future[JsObject] {.importcpp: "initSqlJs(#)".}

proc newDb*(SQL: JsObject, data: JsObject): JsObject {.importcpp: "new #.Database(#)".}

proc jsItem*(arr: JsObject, idx: int): JsObject {.importcpp: "#[#]".}

proc querySelectorAll*(
  el: Element, sel: kstring
): JsObject {.importcpp: "#.querySelectorAll(#)".}

proc closest*(el: Element, sel: kstring): Element {.importcpp: "#.closest(#)".}

proc scrollIntoViewNearest*(
  el: Element
) {.importcpp: "#.scrollIntoView({block:'nearest'})".}

proc smoothScroll*(
  el: Element
) {.importcpp: "#.scrollIntoView({behavior:'smooth',block:'start'})".}

proc prefersReducedMotion*(): bool {.
  importcpp: "window.matchMedia('(prefers-reduced-motion: reduce)').matches"
.}

proc requestAnimationFrame*(fn: proc()) {.importcpp: "requestAnimationFrame(#)".}

proc setGlobalCpSelect*(
  fn: proc(v: kstring)
) {.importcpp: "window.cpSelectSetValue = #".}

proc normalizeWord*(s: kstring): kstring {.importcpp: "#.toLowerCase()".}

proc removeNumberTag*(
  s: kstring
): kstring {.importcpp: "#.replace(/\\s*\\(\\d+\\)/g,'').trim()".}

proc fuzzyNormWord*(
  s: kstring
): kstring {.importcpp: "#.toLowerCase().replace(/[^a-z0-9\\u0080-\\uffff]/g,'')".}

proc replaceHeadword*(
  example, headword: kstring
): kstring {.importcpp: "#.replace(/--|~/g,#)".}

proc htmlEsc*(s: kstring): kstring {.
  importcpp: """
  String(#||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')
"""
.}

proc nextChar*(s: kstring): kstring =
  {.
    emit:
      """`result` = (`s`.length===0?'\xff':`s`.slice(0,-1)+String.fromCharCode(`s`.charCodeAt(`s`.length-1)+1));"""
  .}

proc jsStrEsc*(s: kstring): kstring {.
  importcpp: """
  String(#||'').replace(/\\/g,'\\\\').replace(/"/g,'\\"')
"""
.}

proc pushState*(url: kstring) {.importcpp: "history.pushState(null,'',#)".}

proc replaceState*(url: kstring) {.importcpp: "history.replaceState(null,'',#)".}

proc pathToQuery*(
  path: kstring
): kstring {.importcpp: "decodeURIComponent((#).slice(1))".}

proc buildDataButton*(
    text, action, attrValue: kstring, ariaLabel: kstring = ""
): kstring =
  let htmlText = htmlEsc(text)
  let aria: kstring =
    if ariaLabel != "":
      " aria-label=\"" & htmlEsc(ariaLabel) & "\""
    else:
      ""
  case $action
  of "search":
    return
      "<button class=\"inline-link\" data-action=\"search\" data-query=\"" &
      htmlEsc(attrValue) & "\"" & aria & ">" & htmlText & "</button>"
  of "search-id":
    return
      "<button class=\"xref-link\" data-action=\"search-id\" data-id=\"" & attrValue &
      "\"" & aria & ">" & htmlText & "</button>"
  else:
    return "<button>" & htmlText & "</button>"
