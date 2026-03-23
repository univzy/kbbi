import karax/[kbase, vdom, karaxdsl, karax, kdom, jstrutils]
import ../[types, modes, appstate, ffi]

proc renderGroupHeader(text, colorClass: kstring): VNode =
  buildHtml(tdiv(class = "cp-select__group-hdr")):
    span(class = "cp-grp__line")
    span(class = kstring("cp-grp__text ") & colorClass):
      text text
    let lineSuffix: kstring =
      if colorClass == "cp-grp__text--yellow":
        "cp-grp__line--yellow"
      elif colorClass == "cp-grp__text--cyan":
        "cp-grp__line--cyan"
      else:
        "cp-grp__line--mag"
    span(class = kstring("cp-grp__line ") & lineSuffix)

proc renderDropdown*(): VNode =
  let isOpen = state.dropdownOpen
  var lastGroup: kstring = ""

  buildHtml(
    tdiv(
      id = "cp-select",
      class = kstring("cp-select") & (if isOpen: kstring(" is-open")
      else: kstring("")),
      role = "combobox",
      "aria-haspopup" = "listbox",
      "aria-expanded" = (if isOpen: kstring("true") else: kstring("false")),
      tabindex = "0",
    )
  ):
    proc onclick(ev: Event, n: VNode) =
      let target = cast[kdom.Element](ev.target)
      var opt = target.closest(".cp-select__option[data-value]")
      if not opt.isNil:
        let valStr = opt.getAttribute("data-value")
        for item in dropdownItems:
          if modeToString(item.value) == valStr:
            state.mode = item.value
            state.dropdownOpen = false
            if isKatMode(state.mode):
              state.katFilter = ""
            redraw()
            let inp = document.getElementById("search-input")
            if not inp.isNil:
              inp.focus()
            return
      if not isOpen:
        state.highlightedIdx = block:
          var idx = 0
          for i, item in dropdownItems:
            if item.value == state.mode:
              idx = i
              break
          idx
      state.dropdownOpen = not isOpen
      redraw()
      if isKatMode(state.mode):
        let katInp = document.getElementById("kat-filter-input")
        if not katInp.isNil:
          katInp.focus()

    proc onkeydown(ev: Event, n: VNode) =
      let kev = cast[KeyboardEvent](ev)
      let key = kev.key
      let optCount = dropdownItems.len

      if key == "Escape":
        ev.preventDefault()
        state.dropdownOpen = false
        redraw()
      elif key == "Enter" or key == " ":
        ev.preventDefault()
        if not isOpen:
          state.dropdownOpen = true
          state.highlightedIdx = block:
            var idx = 0
            for i, item in dropdownItems:
              if item.value == state.mode:
                idx = i
                break
            idx
          redraw()
        else:
          let pickedItem = dropdownItems[state.highlightedIdx]
          state.mode = pickedItem.value
          state.dropdownOpen = false
          if isKatMode(state.mode):
            state.katFilter = ""
            redraw()
            let katInpKb = document.getElementById("kat-filter-input")
            if not katInpKb.isNil:
              katInpKb.focus()
          else:
            redraw()
            let inpKb = document.getElementById("search-input")
            if not inpKb.isNil:
              inpKb.focus()
      elif key == "ArrowDown":
        ev.preventDefault()
        if not isOpen:
          state.dropdownOpen = true
          state.highlightedIdx = block:
            var idx = 0
            for i, item in dropdownItems:
              if item.value == state.mode:
                idx = i
                break
            idx
        else:
          state.highlightedIdx = min(state.highlightedIdx + 1, optCount - 1)
        redraw()
        let panel = document.getElementById("cp-select-panel")
        if not panel.isNil:
          let opts = querySelectorAll(panel, ".cp-select__option")
          let highlighted = cast[Element](jsItem(opts, state.highlightedIdx))
          if not highlighted.isNil:
            scrollIntoViewNearest(highlighted)
      elif key == "ArrowUp":
        ev.preventDefault()
        if not isOpen:
          state.dropdownOpen = true
          state.highlightedIdx = block:
            var idx = 0
            for i, item in dropdownItems:
              if item.value == state.mode:
                idx = i
                break
            idx
        else:
          state.highlightedIdx = max(state.highlightedIdx - 1, 0)
        redraw()
        let panel2 = document.getElementById("cp-select-panel")
        if not panel2.isNil:
          let opts2 = querySelectorAll(panel2, ".cp-select__option")
          let highlighted2 = cast[Element](jsItem(opts2, state.highlightedIdx))
          if not highlighted2.isNil:
            scrollIntoViewNearest(highlighted2)

    tdiv(class = "cp-select__trigger"):
      span(class = "cp-select__glyph"):
        text "☒"
      span(class = "cp-select__label"):
        text modeLabel(state.mode)
      span(class = "cp-select__chevron"):
        verbatim """<svg width="9" height="6" viewBox="0 0 9 6" fill="none"><path d="M0.5 0.5L4.5 4.5L8.5 0.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="square" stroke-linejoin="miter"/></svg>"""

    tdiv(id = "cp-select-panel", class = "cp-select__panel", role = "listbox"):
      tdiv(class = "cp-select__scanline", "aria-hidden" = "true")
      tdiv(class = "cp-select__panel-inner"):
        for item in dropdownItems:
          if item.group != lastGroup:
            lastGroup = item.group
            var grpTxt: kstring = "// mode"
            var grpCls: kstring = "cp-grp__text--yellow"
            if item.group == "filter":
              grpTxt = "// filter"
              grpCls = "cp-grp__text--cyan"
            elif item.group == "daftar":
              grpTxt = "// daftar"
              grpCls = "cp-grp__text--mag"
            renderGroupHeader(grpTxt, grpCls)

          let isSelected = state.mode == item.value
          var itemIdx = 0
          for ii, di in dropdownItems:
            if di.value == item.value:
              itemIdx = ii
              break
          let isHighlighted = isOpen and state.highlightedIdx == itemIdx

          var optCls: kstring = "cp-select__option"
          if isSelected:
            optCls = optCls & kstring(" cp-select__option--selected")
          if item.isCyan:
            optCls = optCls & kstring(" cp-select__option--cyan")
          if item.isMag:
            optCls = optCls & kstring(" cp-select__option--mag")
          if isHighlighted:
            optCls = optCls & kstring(" cp-opt--highlighted")

          tdiv(
            class = optCls,
            role = "option",
            tabindex = "-1",
            "data-value" = modeToString(item.value),
          ):
            var dotCls: kstring = "cp-opt__dot"
            if item.isCyan:
              dotCls = dotCls & kstring(" cp-opt__dot--cyan")
            if item.isMag:
              dotCls = dotCls & kstring(" cp-opt__dot--mag")
            span(class = dotCls)
            span(class = "cp-opt__name"):
              text item.label
            if item.group == "mode":
              span(class = "cp-opt__hint"):
                text item.hint
            else:
              var tagCls: kstring = "cp-opt__tag"
              if item.isMag:
                tagCls = tagCls & kstring(" cp-opt__tag--mag")
              span(class = tagCls):
                text item.hint
            span(class = "cp-opt__check"):
              text "⚠"

      span(class = "cp-corner cp-corner--tl", "aria-hidden" = "true")
      span(class = "cp-corner cp-corner--br", "aria-hidden" = "true")

proc pickModeByString*(valStr: kstring) =
  for item in dropdownItems:
    if modeToString(item.value) == valStr:
      state.mode = item.value
      state.dropdownOpen = false
      if isKatMode(state.mode):
        state.katFilter = ""
      redraw()
      return
