import std/strformat

import ./scanner

proc lexeme(token: Token): string =
  result = newString(token.length)
  copyMem(cstring(result), token.start, token.length)

proc compile*(source: var string) =
  initScanner(source)

  var line = -1'i32

  while true:
    let token = scanToken()

    if token.line != line:
      write(stdout, fmt"{token.line: >4} ")
      line = token.line
    else:
      write(stdout, "   | ")

    let lexeme = lexeme(token)

    write(stdout, fmt"{ord(token.`type`): >2} '{lexeme}'{'\n'}")

    if token.`type` == TOKEN_EOF:
      break
