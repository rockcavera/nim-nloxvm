import ./globals, ./types

import ./private/pointer_arithmetics

# vm_impl.nim

proc push*(value: Value) =
  vm.stackTop[] = value
  vm.stackTop += 1

proc pop*(): Value =
  vm.stackTop -= 1
  return vm.stackTop[]

# end
