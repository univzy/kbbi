import karax/[vdom, karaxdsl, compact]

proc renderModeHints*(): VNode {.compact.} =
  buildHtml(tdiv(class = "mode-hints")):
    span(
      class = "mode-hint",
      title = "Coba pencarian persis dulu, jika tidak ketemu lanjut ke pencarian awalan",
    ):
      strong:
        text "Otomatis"
      text " — coba persis dulu, lalu awalan"
    span(
      class = "mode-hint",
      title = "Temukan semua kata yang dimulai dengan teks yang sama",
    ):
      strong:
        text "Awalan"
      text " — semua kata berawalan sama"
    span(
      class = "mode-hint",
      title = "Cari dalam seluruh definisi dan contoh menggunakan FTS5",
    ):
      strong:
        text "Teks penuh"
      text " — cari dalam definisi (FTS5)"
    span(
      class = "mode-hint",
      title = "Masukkan kode kategori opsional dengan kata untuk filter hasil",
    ):
      strong:
        text "Kelas / Bahasa / Bidang / Ragam"
      text " — kata (opsional) + kode mis. "
      em:
        text "n"
      text ", "
      em:
        text "Jw"
      text ", "
      em:
        text "Dok"
      text ", "
      em:
        text "cak"
    span(
      class = "mode-hint",
      title = "Tampilkan semua kode kategori beserta jumlah kata untuk setiap kode",
    ):
      strong:
        text "Daftar …"
      text " — tampilkan semua kode kategori beserta jumlah kata"
