import ./memory, ./value, ./vm

import ./private/pointer_arithmetics

type
  ObjType = enum
    OBJT_STRING

  Obj = object
    `type`: ObjType
    next: ptr Obj

  ObjString = object
    obj: Obj
    length*: int32
    chars*: ptr char

template objType(value: Value): ObjType =
  cast[ptr Obj](asObj(value)).`type`

template isString*(value: Value): bool =
  isObjType(value, OBJT_STRING)

template asString*(value: Value): ptr ObjString =
  cast[ptr ObjString](asObj(value))

template asCString(value: Value): ptr char =
  cast[ptr ObjString](asObj(value)).chars

proc isObjType*(value: Value, `type`: ObjType): bool =
  isObj(value) and cast[ptr Obj](asObj(value)).`type` == `type`

template allocate_obj[T](`type`: typedesc[T], objectType: ObjType): ptr T =
  cast[ptr T](allocateObject(sizeof(`type`), objectType))

proc allocateObject(size: int, `type`: ObjType): ptr Obj =
  result = cast[ptr Obj](reallocate(nil, 0, size))
  result.`type` = `type`
  result.next = vm.objects
  vm.objects = result

proc allocateString(chars: ptr char, length: int32): ptr ObjString =
  result = allocate_obj(ObjString, OBJT_STRING)
  result.length = length
  result.chars = chars

proc takeString*(chars: ptr char, length: int32): ptr ObjString =
  allocateString(chars, length)

proc copyString*(chars: ptr char, length: int32): ptr ObjString =
  var heapChars = allocate(char, length + 1)

  copyMem(heapChars, chars, length)

  heapChars[length] = '\0'

  allocateString(heapChars, length)

proc printObject*(value: Value) =
  case objType(value)
  of OBJT_STRING:
    write(stdout, cast[cstring](asCString(value)))
