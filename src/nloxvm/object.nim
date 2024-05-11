when defined(DEBUG_LOG_GC):
  import std/strformat

import ./chunk, ./globals, ./memory, ./table, ./types, ./value_helpers

import ./private/pointer_arithmetics

template allocate_obj[T](`type`: typedesc[T], objectType: ObjType): ptr T =
  cast[ptr T](allocateObject(sizeof(`type`), objectType))

proc allocateObject(size: int, `type`: ObjType): ptr Obj =
  result = cast[ptr Obj](reallocate(nil, 0, size))
  result.`type` = `type`
  result.isMarked = false
  result.next = vm.objects
  vm.objects = result

  when defined(DEBUG_LOG_GC):
    write(stdout, fmt"{cast[uint](result)} allocate {size} for {ord(`type`)}{'\n'}")

proc newBoundMethod*(receiver: Value, `method`: ptr ObjClosure): ptr ObjBoundMethod =
  result = allocate_obj(ObjBoundMethod, OBJT_BOUND_METHOD)
  result.receiver = receiver
  result.`method` = `method`

proc newClass*(name: ptr ObjString): ptr ObjClass =
  result = allocate_obj(ObjClass, OBJT_CLASS)
  result.name = name

  initTable(result.methods)

proc newClosure*(function: ptr ObjFunction): ptr ObjClosure =
  var upvalues = allocate(ptr ObjUpvalue, function.upvalueCount)

  for i in 0 ..< function.upvalueCount:
    upvalues[i] = nil

  result = allocate_obj(ObjClosure, OBJT_CLOSURE)
  result.function = function
  result.upvalues = upvalues
  result.upvalueCount = function.upvalueCount

proc newFunction*(): ptr ObjFunction =
  result = allocate_obj(ObjFunction, OBJT_FUNCTION)
  result.arity = 0
  result.upvalueCount = 0
  result.name = nil

  initChunk(result.chunk)

proc newInstance*(klass: ptr ObjClass): ptr ObjInstance =
  result = allocate_obj(ObjInstance, OBJT_INSTANCE)
  result.klass = klass

  initTable(result.fields)

proc newNative*(function: NativeFn): ptr ObjNative =
  result = allocate_obj(ObjNative, OBJT_NATIVE)
  result.function = function

proc push(value: Value) {.importc: "push__nloxvmZvm95impl_u4".}
proc pop(): Value {.importc: "pop__nloxvmZvm95impl_u15".}

proc allocateString(chars: ptr char, length: int32, hash: uint32): ptr ObjString =
  result = allocate_obj(ObjString, OBJT_STRING)
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

proc newUpvalue*(slot: ptr Value): ptr ObjUpvalue =
  result = allocate_obj(ObjUpvalue, OBJT_UPVALUE)
  result.location = slot
  result.closed = nilVal
  result.next = nil
