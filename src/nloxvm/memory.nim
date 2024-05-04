import std/strformat

import system/ansi_c

import ./compiler, ./globals, ./printer, ./table, ./types, ./value

when defined(DEBUG_LOG_GC):
  import ./debug # importação cíclica

import ./private/pointer_arithmetics

const GC_HEAP_GROW_FACTOR {.intdefine.} = 2

proc collectGarbage*()

template allocate*[T](`type`: typedesc[T], count: untyped): ptr T =
  cast[ptr T](reallocate(nil, 0, sizeof(`type`) * count))

template free*[T](`type`: typedesc, `pointer`: T) =
  discard reallocate(`pointer`, sizeof(`type`), 0)

template grow_capacity*[T](capacity: T): T =
  if capacity < 8: 8
  else: capacity * 2

template grow_array*[T](`type`: typedesc, `pointer`: T, oldCount, newCount: untyped): T =
  cast[T](reallocate(`pointer`, sizeof(`type`) * oldCount, sizeof(`type`) * newCount))

template free_array*[T](`type`: typedesc, `pointer`: T, oldCount: untyped) =
  discard reallocate(`pointer`, sizeof(`type`) * oldCount, 0)

proc reallocate*(`pointer`: pointer, oldSize: int, newSize: int): pointer =
  vm.bytesAllocated += newSize - oldSize

  if newSize > oldSize:
    when defined(DEBUG_STRESS_GC):
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

  when defined(DEBUG_LOG_GC):
    write(stdout, fmt"{cast[uint](`object`)} mark ")

    printValue(objVal(`object`))

    write(stdout, '\n')

  `object`.isMarked = true

  if vm.grayCapacity < (vm.grayCount + 1):
    vm.grayCapacity = grow_capacity(vm.grayCapacity)
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

proc blackenObject(`object`: ptr Obj) =
  when defined(DEBUG_LOG_GC):
    write(stdout, fmt"{cast[uint](`object`)} blacken ")

    printValue(objVal(`object`))

    write(stdout, '\n')

  case `object`.`type`
  of OBJT_CLOSURE:
    let closure = cast[ptr ObjClosure](`object`)

    markObject(cast[ptr Obj](closure.function))

    for i in 0 ..< closure.upvalueCount:
      markObject(cast[ptr Obj](closure.upvalues[i]))
  of OBJT_FUNCTION:
    let function = cast[ptr ObjFunction](`object`)

    markObject(cast[ptr Obj](function.name))

    markArray(function.chunk.constants)
  of OBJT_UPVALUE:
    markValue(cast[ptr ObjUpvalue](`object`).closed)
  of OBJT_NATIVE, OBJT_STRING:
    discard

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
  when defined(DEBUG_LOG_GC):
    write(stdout, "-- gc begin\n")

    let before = vm.bytesAllocated

  markRoots()

  traceReferences()

  tableRemoveWhite(vm.strings)

  sweep()

  vm.nextGC = vm.bytesAllocated * GC_HEAP_GROW_FACTOR

  when defined(DEBUG_LOG_GC):
    write(stdout, "-- gc end\n")
    write(stdout, fmt"   collected {before - vm.bytesAllocated} bytes (from {before} to {vm.bytesAllocated}) next at {vm.nextGC}{'\n'}")
