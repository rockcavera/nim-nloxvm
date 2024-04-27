import std/strformat

import ./memory

import ./private/pointer_arithmetics

type
  ValueType = enum
    VAL_BOOL,
    VAL_NIL,
    VAL_NUMBER

  Value* = object
    case `type`: ValueType
    of VAL_BOOL:
      boolean: bool
    of VAL_NIL, VAL_NUMBER:
      number: float

  ValueArray* = object
    capacity: int32
    count*: int32
    values*: ptr Value

template isBool*(value: Value): bool =
  value.`type` == VAL_BOOL

template isNil*(value: Value): bool =
  value.`type` == VAL_NIL

template isNumber*(value: Value): bool =
  value.`type` == VAL_NUMBER

template asBool*(value: Value): bool =
  value.boolean

template asNumber*(value: Value): float =
  value.number

template boolVal*(value: bool): Value =
  Value(`type`: VAL_BOOL, boolean: value)

template nilVal*(): Value =
  Value(`type`: VAL_NIL, number: 0.0'f)

template numberVal*(value: float): Value =
  Value(`type`: VAL_NUMBER, number: value)

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

proc printValue*(value: Value) =
  case value.`type`
  of VAL_BOOL:
    write(stdout, $asBool(value))
  of VAL_NIL:
    write(stdout, "nil")
  of VAL_NUMBER:
    write(stdout, fmt"{asNumber(value):g}")

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
