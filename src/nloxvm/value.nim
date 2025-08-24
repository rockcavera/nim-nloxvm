import ./common, ./memory, ./types, ./value_helpers

import ./private/pointer_arithmetics

proc initValueArray*(`array`: var ValueArray) =
  `array`.values = nil
  `array`.capacity = 0
  `array`.count = 0

proc writeValueArray*(vm: var VM, `array`: var ValueArray, value: Value) =
  if `array`.capacity < (`array`.count + 1):
    let oldCapacity = `array`.capacity

    `array`.capacity = growCapacity(oldCapacity)
    `array`.values = growArray(vm, Value, `array`.values, oldCapacity, `array`.capacity)

  `array`.values[`array`.count] = value
  `array`.count += 1

proc valuesEqual*(a: Value, b: Value): bool =
  when nanBoxing:
    if isNumber(a) and isNumber(b):
      return asNumber(a) == asNumber(b)

    a == b
  else:
    if a.`type` != b.`type`:
      return false

    case a.`type`
    of ValBool:
      return asBool(a) == asBool(b)
    of ValNil:
      return true
    of ValNumber:
      return asNumber(a) == asNumber(b)
    of ValObj:
      asObj(a) == asObj(b)
