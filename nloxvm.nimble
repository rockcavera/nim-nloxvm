# Package

version       = "0.1.0"
author        = "rockcavera"
description   = "nloxvm is a Nim implementation of a bytecode virtual machine for interpreting the Lox programming language"
license       = "MIT"
srcDir        = "src"
bin           = @["nloxvm"]


# Dependencies

requires "nim >= 2.0.0"


task test, "Runs the test suite":
  exec "nim c -r tests/tall"
