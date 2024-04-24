import std/[cmdline, exitprocs]

import ./nloxvm/[main]

when declared(commandLineParams) and declared(paramCount):
  setProgramResult(main(paramCount(), commandLineParams()))
else:
  setProgramResult(main(0, []))
