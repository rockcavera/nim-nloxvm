import system/ansi_c

import ./globals, ./types, ./value_helpers

when defined(debugLogGc):
  import std/strformat

  import ./printer

import ./private/pointer_arithmetics

const gcHeapGrowFactor {.intdefine.} = 2

proc freeChunk(chunk: var Chunk) {.importc: "freeChunk__nloxvmZchunk_u23".}
proc collectGarbage*()

template allocate*[T](`type`: typedesc[T], count: untyped): ptr T =
  cast[ptr T](reallocate(nil, 0, sizeof(`type`) * count))

template free*[T](`type`: typedesc, `pointer`: T) =
  discard reallocate(`pointer`, sizeof(`type`), 0)

template growCapacity*[T](capacity: T): T =
  if capacity < 8: 8
  else: capacity * 2

template growArray*[T](`type`: typedesc, `pointer`: T, oldCount, newCount: untyped): T =
  cast[T](reallocate(`pointer`, sizeof(`type`) * oldCount, sizeof(`type`) * newCount))

template freeArray*[T](`type`: typedesc, `pointer`: T, oldCount: untyped) =
  discard reallocate(`pointer`, sizeof(`type`) * oldCount, 0)

proc reallocate*(`pointer`: pointer, oldSize: int, newSize: int): pointer =
  vm.bytesAllocated += newSize - oldSize

  if newSize > oldSize:
    when defined(debugStressGc):
      collectGarbage()

    if vm.bytesAllocated > vm.nextGC:
      collectGarbage()

  if newSize == 0:
    c_free(`pointer`)
    return nil

  result = c_realloc(`pointer`, newSize.csize_t)

  if isNil(result):
    quit(1)

proc markObject*(`object`: ptr Obj) =
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

proc markValue*(value: Value) =
  if isObj(value):
    markObject(asObj(value))

proc markArray(`array`: var ValueArray) =
  for i in 0 ..< `array`.count:
    markValue(`array`.values[i])

# table.nim

proc markTable(table: var Table) =
  for i in 0 ..< table.capacity:
    let entry = addr table.entries[i]

    markObject(cast[ptr Obj](entry.key))
    markValue(entry.value)

# end

proc blackenObject(`object`: ptr Obj) =
  when defined(debugLogGc):
    write(stdout, fmt"{cast[uint](`object`)} blacken ")

    printValue(objVal(`object`))

    write(stdout, '\n')

  case `object`.`type`
  of ObjtBoundMethod:
    let bound = cast[ptr ObjBoundMethod](`object`)

    markValue(bound.receiver)

    markObject(cast[ptr Obj](bound.`method`))
  of ObjtClass:
    let klass = cast[ptr ObjClass](`object`)

    markObject(cast[ptr Obj](klass.name))

    markTable(klass.methods)
  of ObjtClosure:
    let closure = cast[ptr ObjClosure](`object`)

    markObject(cast[ptr Obj](closure.function))

    for i in 0 ..< closure.upvalueCount:
      markObject(cast[ptr Obj](closure.upvalues[i]))
  of ObjtFunction:
    let function = cast[ptr ObjFunction](`object`)

    markObject(cast[ptr Obj](function.name))

    markArray(function.chunk.constants)
  of ObjtInstance:
    let instance = cast[ptr ObjInstance](`object`)

    markObject(cast[ptr Obj](instance.klass))

    markTable(instance.fields)
  of ObjtUpvalue:
    markValue(cast[ptr ObjUpvalue](`object`).closed)
  of ObjtNative, ObjtString:
    discard

from ./table import freeTable, tableRemoveWhite

proc freeObject*(`object`: ptr Obj) =
  when defined(debugLogGc):
    write(stdout, fmt"{cast[uint](`object`)} free type {ord(`object`.`type`)}{'\n'}")

  case `object`.`type`
  of ObjtBoundMethod:
    free(ObjBoundMethod, `object`)
  of ObjtClass:
    let klass = cast[ptr ObjClass](`object`)

    freeTable(klass.methods)

    free(ObjClass, `object`)
  of ObjtClosure:
    let closure = cast[ptr ObjClosure](`object`)

    freeArray(ptr ObjUpvalue, closure.upvalues, closure.upvalueCount)

    free(ObjClosure, `object`)
  of ObjtFunction:
    let function = cast[ptr ObjFunction](`object`)

    freeChunk(function.chunk)

    free(ObjFunction, `object`)
  of ObjtInstance:
    let instance = cast[ptr ObjInstance](`object`)

    freeTable(instance.fields)

    free(ObjInstance, `object`)
  of ObjtNative:
    free(ObjNative, `object`)
  of ObjtString:
    let string = cast[ptr ObjString](`object`)

    freeArray(char, string.chars, string.length + 1)

    free(ObjString, `object`)
  of ObjtUpvalue:
    free(ObjUpvalue, `object`)

# compiler.nim

proc markCompilerRoots() =
  var compiler = current

  while not isNil(compiler):
    markObject(cast[ptr Obj](compiler.function))

    compiler = compiler.enclosing

# end

proc markRoots() =
  for slot in cast[ptr Value](addr vm.stack) ..< vm.stackTop:
    markValue(slot[])

  for i in 0 ..< vm.frameCount:
    markObject(cast[ptr Obj](vm.frames[i].closure))

  var upvalue = vm.openUpvalues

  while not isNil(upvalue):
    markObject(cast[ptr Obj](upvalue))

    upvalue = upvalue.next

  markTable(vm.globals)

  markCompilerRoots()

  markObject(cast[ptr Obj](vm.initString))

proc traceReferences() =
  while vm.grayCount > 0:
    dec(vm.grayCount)

    let `object` = vm.grayStack[vm.grayCount]

    blackenObject(`object`)

proc sweep() =
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

      freeObject(unreached)

proc collectGarbage*() =
  when defined(debugLogGc):
    write(stdout, "-- gc begin\n")

    let before = vm.bytesAllocated

  markRoots()

  traceReferences()

  tableRemoveWhite(vm.strings)

  sweep()

  vm.nextGC = vm.bytesAllocated * gcHeapGrowFactor

  when defined(debugLogGc):
    write(stdout, "-- gc end\n")
    write(stdout, fmt"   collected {before - vm.bytesAllocated} bytes (from {before} to {vm.bytesAllocated}) next at {vm.nextGC}{'\n'}")

proc freeObjects*() =
  var `object` = vm.objects

  while `object` != nil:
    let next = `object`.next

    freeObject(`object`)

    `object` = next

  c_free(vm.grayStack)
