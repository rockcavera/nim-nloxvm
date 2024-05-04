import ./types

# value.nim

template isBool*(value: Value): bool =
  value.`type` == VAL_BOOL

template isNil*(value: Value): bool =
  value.`type` == VAL_NIL

template isNumber*(value: Value): bool =
  value.`type` == VAL_NUMBER

template isObj*(value: Value): bool =
  value.`type` == VAL_OBJ

template asObj*(value: Value): ptr Obj =
  value.obj

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

template objVal*(`object`: ptr Obj): Value =
  Value(`type`: VAL_OBJ, obj: `object`)

# end
