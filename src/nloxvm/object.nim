when defined(debugLogGc):
  import std/strformat

import ./chunk, ./globals, ./memory, ./table, ./types, ./value_helpers

import ./private/pointer_arithmetics

template allocateObj[T](`type`: typedesc[T], objectType: ObjType): ptr T =
  cast[ptr T](allocateObject(sizeof(`type`), objectType))

proc allocateObject(size: int, `type`: ObjType): ptr Obj =
  result = cast[ptr Obj](reallocate(nil, 0, size))
  result.`type` = `type`
  result.isMarked = false
  result.next = vm.objects
  vm.objects = result

  when defined(debugLogGc):
    write(stdout, fmt"{cast[uint](result)} allocate {size} for {ord(`type`)}{'\n'}")

proc newBoundMethod*(receiver: Value, `method`: ptr ObjClosure): ptr ObjBoundMethod =
  result = allocateObj(ObjBoundMethod, ObjtBoundMethod)
  result.receiver = receiver
  result.`method` = `method`

proc newClass*(name: ptr ObjString): ptr ObjClass =
  result = allocateObj(ObjClass, ObjtClass)
  result.name = name

  initTable(result.methods)

proc newClosure*(function: ptr ObjFunction): ptr ObjClosure =
  var upvalues = allocate(ptr ObjUpvalue, function.upvalueCount)

  for i in 0 ..< function.upvalueCount:
    upvalues[i] = nil

  result = allocateObj(ObjClosure, ObjtClosure)
  result.function = function
  result.upvalues = upvalues
  result.upvalueCount = function.upvalueCount

proc newFunction*(): ptr ObjFunction =
  result = allocateObj(ObjFunction, ObjtFunction)
  result.arity = 0
  result.upvalueCount = 0
  result.name = nil

  initChunk(result.chunk)

proc newInstance*(klass: ptr ObjClass): ptr ObjInstance =
  result = allocateObj(ObjInstance, ObjtInstance)
  result.klass = klass

  initTable(result.fields)

proc newNative*(function: NativeFn): ptr ObjNative =
  result = allocateObj(ObjNative, ObjtNative)
  result.function = function

proc push(value: Value) {.importc: "push__nloxvmZvm95impl_u4".}
proc pop(): Value {.importc: "pop__nloxvmZvm95impl_u15".}

proc allocateString(chars: ptr char, length: int32, hash: uint32): ptr ObjString =
  result = allocateObj(ObjString, ObjtString)
  result.length = length
  result.chars = chars
  result.hash = hash

  push(objVal(result))

  discard tableSet(vm.strings, result, nilVal)

  discard pop()

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
    freeArray(char, chars, length + 1)
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

proc newUpvalue*(slot: ptr Value): ptr ObjUpvalue =
  result = allocateObj(ObjUpvalue, ObjtUpvalue)
  result.location = slot
  result.closed = nilVal
  result.next = nil
