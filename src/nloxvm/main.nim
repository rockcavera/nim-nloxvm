import std/[cmdline, exitprocs]

import ./vm_impl, ./types

proc c_fgets(str: cstring, num: cint, stream: File): cstring {.importc: "fgets", header: "<stdio.h>".}

proc repl(vm: var VM) =
  var line = newString(1024)

  while true:
    write(stdout, "> ")

    if isNil(c_fgets(cstring(line), len(line).cint, stdin)):
      write(stdout, '\n')
      break

    discard interpret(vm, line)

proc runFile(vm: var VM, path: string) =
  var source: string

  try:
    source = readFile(path)
  except IOError:
    write(stderr, "Could not open file \"", path, "\".\n")

    setProgramResult(74)
    return

  if len(source) == 0:
    source = "\0"

  let result = interpret(vm, source)

  case result
  of InterpretCompileError:
    setProgramResult(65)
  of InterpretRuntimeError:
    setProgramResult(70)
  else:
    discard

proc main*() =
  var vm = initVM()

  if paramCount() == 0:
    repl(vm)
  elif paramCount() == 1:
    runFile(vm, paramStr(1))
  else:
    write(stderr, "Usage: nloxvm [path]\n")
    setProgramResult(64)

  freeVM(vm)
