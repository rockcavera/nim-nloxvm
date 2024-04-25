import std/[cmdline, exitprocs, strformat]

import ./vm

proc repl() =
  var line = newString(1024)

  while true:
    write(stdout, "> ")

    let readed = readBuffer(stdin, cstring(line), len(line))

    if readed == 0:
      write(stdout, '\n')
      break

    discard interpret(line)

proc runFile(path: string) =
  var source: string

  try:
    source = readFile(path)
  except IOError:
    write(stderr, fmt"""Could not open file "{path}".{'\n'}""")
    quit(74)

  let result = interpret(source)

  if result == INTERPRET_COMPILE_ERROR:
    quit(65)

  if result == INTERPRET_RUNTIME_ERROR:
    quit(65)

proc main*() =
  initVM()

  if paramCount() == 0:
    repl()
  elif paramCount() == 1:
    runFile(paramStr(1))
  else:
    write(stderr, "Usage: nloxvm [path]\n")
    quit(64)

  freeVM()

  setProgramResult(0)
