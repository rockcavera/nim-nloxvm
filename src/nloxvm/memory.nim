import system/ansi_c

import ./types, ./value_helpers

when defined(debugLogGc):
  import std/strformat

  import ./printer

import ./private/pointer_arithmetics

const gcHeapGrowFactor {.intdefine.} = 2

proc freeChunk(vm: var VM, chunk: var Chunk) {.importc: "freeChunk__nloxvmZchunk_u23".}
proc collectGarbage*(vm: var VM)

template allocate*[T](vm: var VM, `type`: typedesc[T], count: untyped): ptr T =
  cast[ptr T](reallocate(vm, nil, 0, sizeof(`type`) * count))

template free*[T](vm: var VM, `type`: typedesc, `pointer`: T) =
  discard reallocate(vm, `pointer`, sizeof(`type`), 0)

template growCapacity*[T](capacity: T): T =
  if capacity < 8: 8
  else: capacity * 2

template growArray*[T](vm: var VM, `type`: typedesc, `pointer`: T, oldCount, newCount: untyped): T =
  cast[T](reallocate(vm, `pointer`, sizeof(`type`) * oldCount, sizeof(`type`) * newCount))

template freeArray*[T](vm: var VM, `type`: typedesc, `pointer`: T, oldCount: untyped) =
  discard reallocate(vm, `pointer`, sizeof(`type`) * oldCount, 0)

proc reallocate*(vm: var VM, `pointer`: pointer, oldSize: int, newSize: int): pointer =
  vm.bytesAllocated += newSize - oldSize

  if newSize > oldSize:
    when defined(debugStressGc):
      collectGarbage(vm)

    if vm.bytesAllocated > vm.nextGC:
      collectGarbage(vm)

  if newSize == 0:
    c_free(`pointer`)
    return nil

  result = c_realloc(`pointer`, newSize.csize_t)

  if isNil(result):
    quit(1)

proc markObject*(vm: var VM, `object`: ptr Obj) =
  if isNil(`object`):
    return

  if `object`.isMarked:
    return

  when defined(debugLogGc):
    write(stdout, fmt"{cast[uint](`object`)} mark ")

    printValue(objVal(`object`))

    write(stdout, '\n')

  `object`.isMarked = true

  if vm.grayCapacity < (vm.grayCount + 1):
    vm.grayCapacity = growCapacity(vm.grayCapacity)
    vm.grayStack = cast[ptr ptr Obj](c_realloc(vm.grayStack, csize_t(sizeof(ptr Obj) * vm.grayCapacity)))

    if isNil(vm.grayStack):
      quit(1)

  vm.grayStack[vm.grayCount] = `object`

  inc(vm.grayCount)

proc markValue*(vm: var VM, value: Value) =
  if isObj(value):
    markObject(vm, asObj(value))

proc markArray(vm: var VM, `array`: var ValueArray) =
  for i in 0 ..< `array`.count:
    markValue(vm, `array`.values[i])

# table.nim

proc markTable(vm: var VM, table: var Table) =
  for i in 0 ..< table.capacity:
    let entry = addr table.entries[i]

    markObject(vm, cast[ptr Obj](entry.key))
    markValue(vm, entry.value)

# end

proc blackenObject(vm: var VM, `object`: ptr Obj) =
  when defined(debugLogGc):
    write(stdout, fmt"{cast[uint](`object`)} blacken ")

    printValue(objVal(`object`))

    write(stdout, '\n')

  case `object`.`type`
  of ObjtBoundMethod:
    let bound = cast[ptr ObjBoundMethod](`object`)

    markValue(vm, bound.receiver)

    markObject(vm, cast[ptr Obj](bound.`method`))
  of ObjtClass:
    let klass = cast[ptr ObjClass](`object`)

    markObject(vm, cast[ptr Obj](klass.name))

    markTable(vm, klass.methods)
  of ObjtClosure:
    let closure = cast[ptr ObjClosure](`object`)

    markObject(vm, cast[ptr Obj](closure.function))

    for i in 0 ..< closure.upvalueCount:
      markObject(vm, cast[ptr Obj](closure.upvalues[i]))
  of ObjtFunction:
    let function = cast[ptr ObjFunction](`object`)

    markObject(vm, cast[ptr Obj](function.name))

    markArray(vm, function.chunk.constants)
  of ObjtInstance:
    let instance = cast[ptr ObjInstance](`object`)

    markObject(vm, cast[ptr Obj](instance.klass))

    markTable(vm, instance.fields)
  of ObjtUpvalue:
    markValue(vm, cast[ptr ObjUpvalue](`object`).closed)
  of ObjtNative, ObjtString:
    discard

from ./table import freeTable, tableRemoveWhite

proc freeObject*(vm: var VM, `object`: ptr Obj) =
  when defined(debugLogGc):
    write(stdout, fmt"{cast[uint](`object`)} free type {ord(`object`.`type`)}{'\n'}")

  case `object`.`type`
  of ObjtBoundMethod:
    free(vm, ObjBoundMethod, `object`)
  of ObjtClass:
    let klass = cast[ptr ObjClass](`object`)

    freeTable(vm, klass.methods)

    free(vm, ObjClass, `object`)
  of ObjtClosure:
    let closure = cast[ptr ObjClosure](`object`)

    freeArray(vm, ptr ObjUpvalue, closure.upvalues, closure.upvalueCount)

    free(vm, ObjClosure, `object`)
  of ObjtFunction:
    let function = cast[ptr ObjFunction](`object`)

    freeChunk(vm, function.chunk)

    free(vm, ObjFunction, `object`)
  of ObjtInstance:
    let instance = cast[ptr ObjInstance](`object`)

    freeTable(vm, instance.fields)

    free(vm, ObjInstance, `object`)
  of ObjtNative:
    free(vm, ObjNative, `object`)
  of ObjtString:
    let string = cast[ptr ObjString](`object`)

    freeArray(vm, char, string.chars, string.length + 1)

    free(vm, ObjString, `object`)
  of ObjtUpvalue:
    free(vm, ObjUpvalue, `object`)

# compiler.nim

proc markCompilerRoots(vm: var VM) =
  var compiler = vm.currentCompiler

  while not isNil(compiler):
    markObject(vm, cast[ptr Obj](compiler.function))

    compiler = compiler.enclosing

# end

proc markRoots(vm: var VM) =
  for slot in cast[ptr Value](addr vm.stack) ..< vm.stackTop:
    markValue(vm, slot[])

  for i in 0 ..< vm.frameCount:
    markObject(vm, cast[ptr Obj](vm.frames[i].closure))

  var upvalue = vm.openUpvalues

  while not isNil(upvalue):
    markObject(vm, cast[ptr Obj](upvalue))

    upvalue = upvalue.next

  markTable(vm, vm.globals)

  markCompilerRoots(vm)

  markObject(vm, cast[ptr Obj](vm.initString))

proc traceReferences(vm: var VM) =
  while vm.grayCount > 0:
    dec(vm.grayCount)

    let `object` = vm.grayStack[vm.grayCount]

    blackenObject(vm, `object`)

proc sweep(vm: var VM) =
  var
    previous: ptr Obj = nil
    `object` = vm.objects

  while not isNil(`object`):
    if `object`.isMarked:
      `object`.isMarked = false
      previous = `object`
      `object` = `object`.next
    else:
      let unreached = `object`

      `object` = `object`.next

      if not isNil(previous):
        previous.next = `object`
      else:
        vm.objects = `object`

      freeObject(vm, unreached)

proc collectGarbage*(vm: var VM) =
  when defined(debugLogGc):
    write(stdout, "-- gc begin\n")

    let before = vm.bytesAllocated

  markRoots(vm)

  traceReferences(vm)

  tableRemoveWhite(vm.strings)

  sweep(vm)

  vm.nextGC = vm.bytesAllocated * gcHeapGrowFactor

  when defined(debugLogGc):
    write(stdout, "-- gc end\n")
    write(stdout, fmt"   collected {before - vm.bytesAllocated} bytes (from {before} to {vm.bytesAllocated}) next at {vm.nextGC}{'\n'}")

proc freeObjects*(vm: var VM) =
  var `object` = vm.objects

  while `object` != nil:
    let next = `object`.next

    freeObject(vm, `object`)

    `object` = next

  c_free(vm.grayStack)
