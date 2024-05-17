import ./common, ./types

# value.nim

when nanBoxing:
  const
    signBit = 0x8000000000000000'u64
    qnan = 0x7ffc000000000000'u64

    tagNil = 1
    tagFalse = 2
    tagTrue = 3

    falseVal = Value(qnan or tagFalse)
    trueVal = Value(qnan or tagTrue)

  template isBool*(value: Value): bool =
    (value or 1) == trueVal

  template isNil*(value: Value): bool =
    value == nilVal

  template isNumber*(value: Value): bool =
    (value and qnan) != qnan

  template isObj*(value: Value): bool =
    (value and (qnan or signBit)) == (qnan or signBit)

  template asBool*(value: Value): bool =
    value == trueVal

  template asNumber*(value: Value): float =
    valueToNum(value)

  template asObj*(value: Value): ptr Obj =
    cast[ptr Obj](value and not(signBit or qnan))

  template boolVal*(b: bool): Value =
    if b: trueVal
    else: falseVal

  const nilVal* = Value(qnan or tagNil)

  template numberVal*(num: float): Value =
    numToValue(num)

  template objVal*[T: Obj|ObjFunction|ObjNative|ObjString|ObjUpvalue|ObjClosure|ObjClass|ObjInstance|ObjBoundMethod](obj: ptr T): Value =
    Value(signBit or qnan or cast[uint64](obj))

  proc valueToNum*(value: Value): float {.inline.} =
    when defined(nanBoxingWithCast):
      cast[float](value) # for compilers that do not optimize `copyMem()`
    else:
      copyMem(addr result, addr value, sizeof(Value))

  proc numToValue*(num: float): Value {.inline.} =
    when defined(nanBoxingWithCast):
      cast[Value](num) # for compilers that do not optimize `copyMem()`
    else:
      copyMem(addr result, addr num, sizeof(float))
else:
  template isBool*(value: Value): bool =
    value.`type` == ValBool

  template isNil*(value: Value): bool =
    value.`type` == ValNil

  template isNumber*(value: Value): bool =
    value.`type` == ValNumber

  template isObj*(value: Value): bool =
    value.`type` == ValObj

  template asObj*(value: Value): ptr Obj =
    value.obj

  template asBool*(value: Value): bool =
    value.boolean

  template asNumber*(value: Value): float =
    value.number

  template boolVal*(value: bool): Value =
    Value(`type`: ValBool, boolean: value)

  const nilVal* = Value(`type`: ValNil, number: 0.0'f)

  template numberVal*(value: float): Value =
    Value(`type`: ValNumber, number: value)

  template objVal*[T: Obj|ObjFunction|ObjNative|ObjString|ObjUpvalue|ObjClosure|ObjClass|ObjInstance|ObjBoundMethod](`object`: ptr T): Value =
    when T is Obj:
      Value(`type`: ValObj, obj: `object`)
    else:
      Value(`type`: ValObj, obj: cast[ptr Obj](`object`))

# end
