import ./memory, ./types, ./value_helpers

import ./private/pointer_arithmetics

proc initValueArray*(`array`: var ValueArray) =
  `array`.values = nil
  `array`.capacity = 0
  `array`.count = 0

proc writeValueArray*(`array`: var ValueArray, value: Value) =
  if `array`.capacity < (`array`.count + 1):
    let oldCapacity = `array`.capacity

    `array`.capacity = grow_capacity(oldCapacity)
    `array`.values = grow_array(Value, `array`.values, oldCapacity, `array`.capacity)

  `array`.values[`array`.count] = value
  `array`.count += 1

proc freeValueArray*(`array`: var ValueArray) =
  free_array(Value, `array`.values, `array`.capacity)
  initValueArray(`array`)

proc valuesEqual*(a: Value, b: Value): bool =
  if a.`type` != b.`type`:
    return false

  case a.`type`
  of VAL_BOOL:
    return asBool(a) == asBool(b)
  of VAL_NIL:
    return true
  of VAL_NUMBER:
    return asNumber(a) == asNumber(b)
  of VAL_OBJ:
    asObj(a) == asObj(b)
