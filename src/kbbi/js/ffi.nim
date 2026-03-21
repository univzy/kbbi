import std/[dom, jsffi, asyncjs]

proc arrayBuffer*(resp: JsObject): Future[JsObject] {.importjs: "#.arrayBuffer()".}
proc uint8Array*(buf: JsObject): JsObject {.importjs: "new Uint8Array(#)".}
proc initSqlJs*(cfg: JsObject): Future[JsObject] {.importjs: "initSqlJs(#)".}
proc newDb*(SQL: JsObject, data: JsObject): JsObject {.importjs: "new #.Database(#)".}

proc jsGet*(obj: JsObject, key: cstring): JsObject {.importjs: "#[#]".}
proc jsLength*(arr: JsObject): int {.importjs: "(#||[]).length".}
proc jsItem*(arr: JsObject, idx: int): JsObject {.importjs: "#[#]".}
proc jsStr*(obj: JsObject): cstring {.importjs: "String(#||'')".}
proc jsInt*(obj: JsObject): int {.importjs: "(Number(#)||0)".}

proc setInnerHTML*(el: Element, html: cstring) {.importjs: "#.innerHTML = #".}
proc getValue*(el: Element): cstring {.importjs: "#.value".}
proc setValue*(el: Element, v: cstring) {.importjs: "#.value = #".}
proc getById*(id: cstring): Element {.importjs: "document.getElementById(#)".}
proc focusEl*(el: Element) {.importjs: "#.focus()".}
proc smoothScroll*(el: Element) {.importjs: "#.scrollIntoView({behavior:'smooth',block:'start'})".}

proc addKbListener*(el: Element, fn: proc(ev: KeyboardEvent)) {.importjs: "#.addEventListener('keydown',#)".}
proc addClickListener*(el: Element, fn: proc(ev: Event)) {.importjs: "#.addEventListener('click',#)".}
proc addChangeListener*(el: Element, fn: proc(ev: Event)) {.importjs: "#.addEventListener('change',#)".}
proc querySelectorAll*(el: Element, sel: cstring): JsObject {.importjs: "#.querySelectorAll(#)".}
proc contains*(el: Element, other: Element): bool {.importjs: "#.contains(#)".}

proc getAttribute*(el: Element, name: cstring): cstring {.importjs: "#.getAttribute(#)".}
proc setAttribute*(el: Element, name, value: cstring) {.importjs: "#.setAttribute(#,#)".}
proc scrollIntoViewNearest*(el: Element) {.importjs: "#.scrollIntoView({block:'nearest'})".}
proc dispatchChange*(el: Element) {.importjs: "#.dispatchEvent(new Event('change',{bubbles:true}))".}

proc elTextContent*(el: Element, s: cstring) {.importjs: "#.textContent = #".}
proc dataValue*(el: Element): cstring {.importjs: "#.dataset.value".}
proc closestOpt*(el: Element): Element {.importjs: "#.closest('.cp-select__option[data-value]')".}

proc setGlobalCpSelect*(fn: proc(v: cstring)) {.importjs: "window.cpSelectSetValue = #".}
proc localStorageSetItem*(key, value: cstring) {.importjs: "localStorage.setItem(#, #)".}
proc localStorageGetItem*(key: cstring): cstring {.importjs: "localStorage.getItem(#) || ''".}

proc normalizeWord*(s: cstring): cstring {.importjs: """
  (function(s) {
    return s.toLowerCase();
  })(#)
""".}

proc removeNumberTag*(s: cstring): cstring {.importjs: """
  (function(s) {
    return s
      .replace(/\\s*\\(\\d+\\)/g, '')
      .trim();
  })(#)
""".}

proc fuzzyNormWord*(s: cstring): cstring {.importjs: """
  (function(s) {
    return s.toLowerCase()
      .replace(/[^a-z0-9\\u0080-\\uffff]/g, '');
  })(#)
""".}

proc replaceHeadword*(example, headword: cstring): cstring {.importjs: """
  (function(ex, hw) {
    return ex.replace(/--|~/g, hw);
  })(#, #)
""".}

proc htmlEsc*(s: cstring): cstring {.importjs: """
  (function(s) {
    return String(s || '')
      .replace(/&/g,  '&amp;')
      .replace(/</g,  '&lt;')
      .replace(/>/g,  '&gt;')
      .replace(/"/g,  '&quot;');
  })(#)
""".}

proc nextChar*(s: cstring): cstring {.importjs: """
  (function(s) {
    if (s.length === 0) return '\\xff';
    var code = s.charCodeAt(s.length - 1);
    return s.slice(0, -1) + String.fromCharCode(code + 1);
  })(#)
""".}

proc jsStrEsc*(s: cstring): cstring {.importjs: """
  (function(s) {
    return String(s || '')
      .replace(/\\/g, '\\\\')
      .replace(/"/g,  '\\"');
  })(#)
""".}

proc buildDataButton*(text, action, attrValue: cstring, ariaLabel: cstring = ""): cstring =
  let htmlText = htmlEsc(text)
  let aria: cstring = if ariaLabel != "": " aria-label=\"" & htmlEsc(ariaLabel) & "\"" else: ""
  case $action
  of "search":
    let htmlAttr = htmlEsc(attrValue)
    return "<button class=\"inline-link\" data-action=\"search\" data-query=\"" & htmlAttr & "\"" & aria & ">" & htmlText & "</button>"
  of "search-id":
    return "<button class=\"xref-link\" data-action=\"search-id\" data-id=\"" & attrValue & "\"" & aria & ">" & htmlText & "</button>"
  else:
    return "<button>" & htmlText & "</button>"