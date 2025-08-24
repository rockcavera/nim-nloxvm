import ./types

import ./private/pointer_arithmetics

# vm_impl.nim

proc push*(vm: var VM, value: Value) {.inline.} =
  vm.stackTop[] = value
  vm.stackTop += 1

proc pop*(vm: var VM): Value {.inline.} =
  vm.stackTop -= 1
  return vm.stackTop[]

# end
