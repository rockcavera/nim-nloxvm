import ./types, ./value_helpers

# object.nim

template objType*(value: Value): ObjType =
  asObj(value).`type`

template isClass*(value: Value): bool =
  isObjType(value, OBJT_CLASS)

template isClosure*(value: Value): bool =
  isObjType(value, OBJT_CLOSURE)

template isFunction*(value: Value): bool =
  isObjType(value, OBJT_FUNCTION)

template isInstance*(value: Value): bool =
  isObjType(value, OBJT_INSTANCE)

template isNative*(value: Value): bool =
  isObjType(value, OBJT_NATIVE)

template isString*(value: Value): bool =
  isObjType(value, OBJT_STRING)

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

proc isObjType*(value: Value, `type`: ObjType): bool =
  isObj(value) and asObj(value).`type` == `type`

# end
