import ./[types]

var state* = AppState(
  mode: ModeAuto,
  query: "",
  katFilter: "",
  resultHtml: "",
  hasResult: false,
  isLoading: false,
  isDbReady: false,
  dbError: "",
  dropdownOpen: false,
)
