import ./globals, ./memory, ./value, ./table, ./types

import ./private/pointer_arithmetics

template objType(value: Value): ObjType =
  asObj(value).`type`

template isString*(value: Value): bool =
  isObjType(value, OBJT_STRING)

template asString*(value: Value): ptr ObjString =
  cast[ptr ObjString](asObj(value))

template asCString(value: Value): ptr char =
  cast[ptr ObjString](asObj(value)).chars

proc isObjType*(value: Value, `type`: ObjType): bool =
  isObj(value) and asObj(value).`type` == `type`

template allocate_obj[T](`type`: typedesc[T], objectType: ObjType): ptr T =
  cast[ptr T](allocateObject(sizeof(`type`), objectType))

proc allocateObject(size: int, `type`: ObjType): ptr Obj =
  result = cast[ptr Obj](reallocate(nil, 0, size))
  result.`type` = `type`
  result.next = vm.objects
  vm.objects = result

proc allocateString(chars: ptr char, length: int32, hash: uint32): ptr ObjString =
  result = allocate_obj(ObjString, OBJT_STRING)
  result.length = length
  result.chars = chars
  result.hash = hash

  discard tableSet(vm.strings, result, nilVal())

proc hashString(key: ptr char, length: int32): uint32 =
  result = 2166136261'u32

  for i in 0 ..< length:
    result = result xor uint32(key[i])
    result *= 16777619'u32

proc takeString*(chars: ptr char, length: int32): ptr ObjString =
  let
    hash = hashString(chars, length)
    interned = tableFindString(vm.strings, chars, length, hash)

  if not isNil(interned):
    free_array(char, chars, length + 1)
    return interned

  allocateString(chars, length, hash)

proc copyString*(chars: ptr char, length: int32): ptr ObjString =
  let
    hash = hashString(chars, length)
    interned = tableFindString(vm.strings, chars, length, hash)

  if not isNil(interned):
    return interned

  var heapChars = allocate(char, length + 1)

  copyMem(heapChars, chars, length)

  heapChars[length] = '\0'

  allocateString(heapChars, length, hash)

proc printObject*(value: Value) =
  case objType(value)
  of OBJT_STRING:
    write(stdout, cast[cstring](asCString(value)))
