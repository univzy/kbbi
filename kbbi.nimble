# Package

version       = "0.0.1"
author        = "univzy"
description   = "KBBI - Kamus Besar Bahasa Indonesia"
license       = "MIT"
srcDir        = "src"

# Tasks
task builddb, "Build database builder":
  mkDir "bin"
  exec "nim c --passL:-s --out:bin/kbbi_build src/kbbi_build.nim"

task buildse, "Build database search":
  mkDir "bin"
  exec "nim c --passL:-s --out:bin/kbbi_search src/kbbi_search.nim"

task buildjs, "Build JavaScript frontend":
  exec "nim js --out:pages/kbbi.js src/kbbi_js.nim"

task buildall, "Build all targets":
  mkDir "bin"
  exec "nim c --passL:-s --out:bin/kbbi_build src/kbbi_build.nim"
  exec "nim c --passL:-s --out:bin/kbbi_search src/kbbi_search.nim"
  exec "nim js --out:pages/kbbi.js src/kbbi_js.nim"

# Dependencies

requires "nim >= 2.2.8"

requires "zippy >= 0.10.19"
requires "db_connector >= 0.1.0"