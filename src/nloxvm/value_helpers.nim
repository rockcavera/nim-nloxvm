import ./common, ./types

# value.nim

when NAN_BOXING:
  const
    SIGN_BIT = 0x8000000000000000'u64
    QNAN = 0x7ffc000000000000'u64

    TAG_NIL = 1
    TAG_FALSE = 2
    TAG_TRUE = 3

    falseVal = Value(QNAN or TAG_FALSE)
    trueVal = Value(QNAN or TAG_TRUE)

  template isBool*(value: Value): bool =
    (value or 1) == trueVal

  template isNil*(value: Value): bool =
    value == nilVal

  template isNumber*(value: Value): bool =
    (value and QNAN) != QNAN

  template isObj*(value: Value): bool =
    (value and (QNAN or SIGN_BIT)) == (QNAN or SIGN_BIT)

  template asBool*(value: Value): bool =
    value == trueVal

  template asNumber*(value: Value): float =
    valueToNum(value)

  template asObj*(value: Value): ptr Obj =
    cast[ptr Obj](value and not(SIGN_BIT or QNAN))

  template boolVal*(b: bool): Value =
    if b: trueVal
    else: falseVal

  const nilVal* = Value(QNAN or TAG_NIL)

  template numberVal*(num: float): Value =
    numToValue(num)

  template objVal*(obj: ptr Obj): Value =
    Value(SIGN_BIT or QNAN or cast[uint64](obj))

  proc valueToNum*(value: Value): float {.inline.} =
    when defined(NAN_BOXING_WITH_CAST):
      cast[float](value) # for compilers that do not optimize `copyMem()`
    else:
      copyMem(addr result, addr value, sizeof(Value))

  proc numToValue*(num: float): Value {.inline.} =
    when defined(NAN_BOXING_WITH_CAST):
      cast[Value](num) # for compilers that do not optimize `copyMem()`
    else:
      copyMem(addr result, addr num, sizeof(float))
else:
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

  const nilVal* = Value(`type`: VAL_NIL, number: 0.0'f)

  template numberVal*(value: float): Value =
    Value(`type`: VAL_NUMBER, number: value)

  template objVal*(`object`: ptr Obj): Value =
    Value(`type`: VAL_OBJ, obj: `object`)

# end
