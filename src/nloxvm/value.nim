import std/strformat

import ./memory

type
  Value* = float

  ValueArray* = object
    capacity: int32
    count*: int32
    values*: ptr UncheckedArray[Value]

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
  write(stdout, fmt"{value:.2}")
