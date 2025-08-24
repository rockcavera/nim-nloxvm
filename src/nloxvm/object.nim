when defined(debugLogGc):
  import std/strformat

import ./chunk, ./memory, ./table, ./types, ./value_helpers, ./vm_helpers

import ./private/pointer_arithmetics

template allocateObj[T](vm: var VM, `type`: typedesc[T], objectType: ObjType): ptr T =
  cast[ptr T](allocateObject(vm, sizeof(`type`), objectType))

proc allocateObject(vm: var VM, size: int, `type`: ObjType): ptr Obj =
  result = cast[ptr Obj](reallocate(vm, nil, 0, size))
  result.`type` = `type`
  result.isMarked = false
  result.next = vm.objects
  vm.objects = result

  when defined(debugLogGc):
    write(stdout, fmt"{cast[uint](result)} allocate {size} for {ord(`type`)}{'\n'}")

proc newBoundMethod*(vm: var VM, receiver: Value, `method`: ptr ObjClosure): ptr ObjBoundMethod =
  result = allocateObj(vm, ObjBoundMethod, ObjtBoundMethod)
  result.receiver = receiver
  result.`method` = `method`

proc newClass*(vm: var VM, name: ptr ObjString): ptr ObjClass =
  result = allocateObj(vm, ObjClass, ObjtClass)
  result.name = name

  initTable(result.methods)

proc newClosure*(vm: var VM, function: ptr ObjFunction): ptr ObjClosure =
  var upvalues = allocate(vm, ptr ObjUpvalue, function.upvalueCount)

  for i in 0 ..< function.upvalueCount:
    upvalues[i] = nil

  result = allocateObj(vm, ObjClosure, ObjtClosure)
  result.function = function
  result.upvalues = upvalues
  result.upvalueCount = function.upvalueCount

proc newFunction*(vm: var VM): ptr ObjFunction =
  result = allocateObj(vm, ObjFunction, ObjtFunction)
  result.arity = 0
  result.upvalueCount = 0
  result.name = nil

  initChunk(result.chunk)

proc newInstance*(vm: var VM, klass: ptr ObjClass): ptr ObjInstance =
  result = allocateObj(vm, ObjInstance, ObjtInstance)
  result.klass = klass

  initTable(result.fields)

proc newNative*(vm: var VM, function: NativeFn): ptr ObjNative =
  result = allocateObj(vm, ObjNative, ObjtNative)
  result.function = function

proc allocateString(vm: var VM, chars: ptr char, length: int32, hash: uint32): ptr ObjString =
  result = allocateObj(vm, ObjString, ObjtString)
  result.length = length
  result.chars = chars
  result.hash = hash

  push(vm, objVal(result))

  discard tableSet(vm, vm.strings, result, nilVal)

  discard pop(vm)

proc hashString(key: ptr char, length: int32): uint32 =
  result = 2166136261'u32

  for i in 0 ..< length:
    result = result xor uint32(key[i])
    result *= 16777619'u32

proc takeString*(vm: var VM, chars: ptr char, length: int32): ptr ObjString =
  let
    hash = hashString(chars, length)
    interned = tableFindString(vm.strings, chars, length, hash)

  if not isNil(interned):
    freeArray(vm, char, chars, length + 1)
    return interned

  allocateString(vm, chars, length, hash)

proc copyString*(vm: var VM, chars: ptr char, length: int32): ptr ObjString =
  let
    hash = hashString(chars, length)
    interned = tableFindString(vm.strings, chars, length, hash)

  if not isNil(interned):
    return interned

  var heapChars = allocate(vm, char, length + 1)

  copyMem(heapChars, chars, length)

  heapChars[length] = '\0'

  allocateString(vm, heapChars, length, hash)

proc newUpvalue*(vm: var VM, slot: ptr Value): ptr ObjUpvalue =
  result = allocateObj(vm, ObjUpvalue, ObjtUpvalue)
  result.location = slot
  result.closed = nilVal
  result.next = nil
