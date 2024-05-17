import ./types, ./value_helpers

# object.nim

template objType*(value: Value): ObjType =
  asObj(value).`type`

template isBoundMethod*(value: Value): bool =
  isObjType(value, ObjtBoundMethod)

template isClass*(value: Value): bool =
  isObjType(value, ObjtClass)

template isClosure*(value: Value): bool =
  isObjType(value, ObjtClosure)

template isFunction*(value: Value): bool =
  isObjType(value, ObjtFunction)

template isInstance*(value: Value): bool =
  isObjType(value, ObjtInstance)

template isNative*(value: Value): bool =
  isObjType(value, ObjtNative)

template isString*(value: Value): bool =
  isObjType(value, ObjtString)

template asBoundMethod*(value: Value): ptr ObjBoundMethod =
  cast[ptr ObjBoundMethod](asObj(value))

template asClass*(value: Value): ptr ObjClass =
  cast[ptr ObjClass](asObj(value))

template asClosure*(value: Value): ptr ObjClosure =
  cast[ptr ObjClosure](asObj(value))

template asFunction*(value: Value): ptr ObjFunction =
  cast[ptr ObjFunction](asObj(value))

template asInstance*(value: Value): ptr ObjInstance =
  cast[ptr ObjInstance](asObj(value))

template asNative*(value: Value): NativeFn =
  cast[ptr ObjNative](asObj(value)).function

template asString*(value: Value): ptr ObjString =
  cast[ptr ObjString](asObj(value))

template asCString*(value: Value): ptr char =
  cast[ptr ObjString](asObj(value)).chars

proc isObjType*(value: Value, `type`: ObjType): bool {.inline.} =
  isObj(value) and asObj(value).`type` == `type`

# end
