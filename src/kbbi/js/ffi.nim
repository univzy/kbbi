import std/[dom, jsffi, asyncjs]

proc arrayBuffer*(resp: JsObject): Future[JsObject] {.
  importjs: """
  (function(r) {
    return r.arrayBuffer(); 
  })(#)
"""
.}

proc uint8Array*(buf: JsObject): JsObject {.
  importjs: """
  (function(b) {
    return new Uint8Array(b); 
  })(#)
"""
.}

proc initSqlJs*(cfg: JsObject): Future[JsObject] {.
  importjs: """
  (function(c) {
    return initSqlJs(c); 
  })(#)
"""
.}

proc newDb*(SQL: JsObject, data: JsObject): JsObject {.
  importjs: """
  (function(sql, d) {
    return new sql.Database(d); 
  })(#, #)
"""
.}

proc jsGet*(obj: JsObject, key: cstring): JsObject {.
  importjs: """
  (function(o, k) {
    return o[k];
  })(#, #)
"""
.}

proc jsLength*(o: JsObject): int {.
  importjs: """
  (function(v) {
    return v==null||v==undefined ? 0 :
           Array.isArray(v) ? v.length :
           typeof v==="object" ? Object.keys(v).length : 0;
  })(#)
"""
.}

proc jsItem*(arr: JsObject, idx: int): JsObject {.
  importjs: """
  (function(a, i) {
    return a[i];
  })(#, #)
"""
.}

proc jsStr*(obj: JsObject): cstring {.
  importjs: """
  (function(v) {
    return String(v || '');
  })(#)
"""
.}

proc jsInt*(obj: JsObject): int {.
  importjs: """
  (function(v) {
    return Number(v) || 0; 
  })(#)
"""
.}

proc setInnerHTML*(el: Element, html: cstring) {.
  importjs: """
  (function(e, h) {
    e.innerHTML = h;
  })(#, #)
"""
.}

proc getValue*(el: Element): cstring {.
  importjs: """
  (function(e) {
    return e.value;
  })(#)
"""
.}

proc setValue*(el: Element, v: cstring) {.
  importjs: """
  (function(e, val) {
    e.value = val;
  })(#, #)
"""
.}

proc getById*(id: cstring): Element {.
  importjs: """
  (function(i) {
    return document.getElementById(i);
  })(#)
"""
.}

proc focusEl*(el: Element) {.
  importjs: """
  (function(e) {
    e.focus();
  })(#)
"""
.}

proc smoothScroll*(el: Element) {.
  importjs: """
  (function(e) {
    e.scrollIntoView({behavior: 'smooth', block: 'start'});
  })(#)
"""
.}

proc addKbListener*(el: Element, fn: proc(ev: KeyboardEvent)) {.
  importjs: """
  (function(e, f) {
    e.addEventListener('keydown', f);
  })(#, #)
"""
.}

proc addClickListener*(el: Element, fn: proc(ev: Event)) {.
  importjs: """
  (function(e, f) {
    e.addEventListener('click', f);
  })(#, #)
"""
.}

proc addChangeListener*(el: Element, fn: proc(ev: Event)) {.
  importjs: """
  (function(e, f) {
    e.addEventListener('change', f);
  })(#, #)
"""
.}

proc querySelectorAll*(el: Element, sel: cstring): JsObject {.
  importjs: """
  (function(e, s) {
    return e.querySelectorAll(s);
  })(#, #)
"""
.}

proc contains*(el: Element, other: Element): bool {.
  importjs: """
  (function(e, o) {
    return e.contains(o);
  })(#, #)
"""
.}

proc getAttribute*(el: Element, name: cstring): cstring {.
  importjs: """
  (function(e, n) {
    return e.getAttribute(n);
  })(#, #)
"""
.}

proc setAttribute*(el: Element, name, value: cstring) {.
  importjs: """
  (function(e, n, v) {
    e.setAttribute(n, v);
  })(#, #, #)
"""
.}

proc scrollIntoViewNearest*(el: Element) {.
  importjs: """
  (function(e) {
    e.scrollIntoView({block: 'nearest'});
  })(#)
"""
.}

proc dispatchChange*(el: Element) {.
  importjs: """
  (function(e) {
    e.dispatchEvent(new Event('change', {bubbles: true}));
  })(#)
"""
.}

proc elTextContent*(el: Element, s: cstring) {.
  importjs: """
  (function(e, t) {
    e.textContent = t;
  })(#, #)
"""
.}

proc dataValue*(el: Element): cstring {.
  importjs: """
  (function(e) {
    return e.dataset.value;
  })(#)
"""
.}

proc closestOpt*(el: Element): Element {.
  importjs: """
  (function(e) {
    return e.closest('.cp-select__option[data-value]');
  })(#)
"""
.}

proc setGlobalCpSelect*(fn: proc(v: cstring)) {.
  importjs: """
  (function(f) {
    window.cpSelectSetValue = f;
  })(#)
"""
.}

proc localStorageSetItem*(key, value: cstring) {.
  importjs: """
  (function(k, v) {
    localStorage.setItem(k, v);
  })(#, #)
"""
.}

proc localStorageGetItem*(key: cstring): cstring {.
  importjs: """
  (function(k) {
    return localStorage.getItem(k) || '';
  })(#)
"""
.}

proc normalizeWord*(s: cstring): cstring {.
  importjs: """
  (function(s) {
    return s.toLowerCase();
  })(#)
"""
.}

proc removeNumberTag*(s: cstring): cstring {.
  importjs: """
  (function(s) {
    return s
      .replace(/\\s*\\(\\d+\\)/g, '')
      .trim();
  })(#)
"""
.}

proc fuzzyNormWord*(s: cstring): cstring {.
  importjs: """
  (function(s) {
    return s.toLowerCase()
      .replace(/[^a-z0-9\\u0080-\\uffff]/g, '');
  })(#)
"""
.}

proc replaceHeadword*(example, headword: cstring): cstring {.
  importjs: """
  (function(ex, hw) {
    return ex.replace(/--|~/g, hw);
  })(#, #)
"""
.}

proc htmlEsc*(s: cstring): cstring {.
  importjs: """
  (function(s) {
    return String(s || '')
      .replace(/&/g,  '&amp;')
      .replace(/</g,  '&lt;')
      .replace(/>/g,  '&gt;')
      .replace(/"/g,  '&quot;');
  })(#)
"""
.}

proc nextChar*(s: cstring): cstring {.
  importjs: """
  (function(s) {
    if (s.length === 0) return '\\xff';
    var code = s.charCodeAt(s.length - 1);
    return s.slice(0, -1) + String.fromCharCode(code + 1);
  })(#)
"""
.}

proc jsStrEsc*(s: cstring): cstring {.
  importjs: """
  (function(s) {
    return String(s || '')
      .replace(/\\/g, '\\\\')
      .replace(/"/g,  '\\"');
  })(#)
"""
.}

proc buildDataButton*(
    text, action, attrValue: cstring, ariaLabel: cstring = ""
): cstring =
  let htmlText = htmlEsc(text)
  let aria: cstring =
    if ariaLabel != "":
      " aria-label=\"" & htmlEsc(ariaLabel) & "\""
    else:
      ""
  case $action
  of "search":
    let htmlAttr = htmlEsc(attrValue)
    return
      "<button class=\"inline-link\" data-action=\"search\" data-query=\"" & htmlAttr &
      "\"" & aria & ">" & htmlText & "</button>"
  of "search-id":
    return
      "<button class=\"xref-link\" data-action=\"search-id\" data-id=\"" & attrValue &
      "\"" & aria & ">" & htmlText & "</button>"
  else:
    return "<button>" & htmlText & "</button>"
