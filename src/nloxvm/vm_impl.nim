import std/[strutils, times]

import ./compiler, ./memory, ./object, ./object_helpers, ./printer, ./table, ./types, ./value, ./value_helpers, ./vm_helpers

when defined(debugTraceExecution):
  import ./debug

import ./private/pointer_arithmetics

when defined(nloxvmBenchmark):
  import std/monotimes

  proc clockNative(argCount: int32, args: ptr Value): Value =
    let
      current = ticks(getMonoTime())
      milliseconds = float(convert(Nanoseconds, Milliseconds, current))

    numberVal(milliseconds / 1000.0)
else:
  proc clockNative(argCount: int32, args: ptr Value): Value =
    numberVal(cpuTime())

proc resetStack(vm: var VM) =
  vm.stackTop = addr vm.stack[0]
  vm.frameCount = 0
  vm.openUpvalues = nil

proc runtimeError(vm: var VM, format: string, args: varargs[string, `$`]) =
  if len(args) > 0:
    write(stderr, format % args)
  else:
    write(stderr, format)

  write(stderr, '\n')

  for i in countdown(vm.frameCount - 1, 0):
    let
      frame = addr vm.frames[i]
      function = frame.closure.function
      instruction = frame.ip - function.chunk.code - 1

    write(stderr, "[line ", $function.chunk.lines[instruction], "] in ")

    if isNil(function.name):
      write(stderr, "script\n")
    else:
      discard writeBuffer(stderr, function.name.chars, function.name.length)

      write(stderr, "()\n")

  resetStack(vm)

proc defineNative(vm: var VM, name: cstring, function: NativeFn) =
  push(vm, objVal(copyString(vm, cast[ptr char](name), len(name).int32)))
  push(vm, objVal(newNative(vm, function)))

  discard tableSet(vm, vm.globals, asString(vm.stack[0]), vm.stack[1])

  discard pop(vm)
  discard pop(vm)

proc initVM*(): VM =
  resetStack(result)

  result.objects = nil
  result.bytesAllocated = 0
  result.nextGC = 1024 * 1024

  result.grayCount = 0
  result.grayCapacity = 0
  result.grayStack = nil

  initTable(result.globals)
  initTable(result.strings)

  result.initString = nil
  result.initString = copyString(result, cast[ptr char](cstring"init"), 4)

  result.currentCompiler = nil

  defineNative(result, cstring"clock", clockNative)

proc freeVM*(vm: var VM) =
  freeTable(vm, vm.globals)
  freeTable(vm, vm.strings)

  vm.initString = nil

  freeObjects(vm)

proc peek(vm: var VM, distance: int32): Value =
  vm.stackTop[-1 - distance]

proc call(vm: var VM, closure: ptr ObjClosure, argCount: int32): bool =
  if argCount != closure.function.arity:
    runtimeError(vm, "Expected $1 arguments but got $2.", closure.function.arity, argCount)
    return false

  if vm.frameCount == framesMax:
    runtimeError(vm, "Stack overflow.")
    return false

  var frame = addr vm.frames[vm.frameCount]

  inc(vm.frameCount)

  frame.closure = closure
  frame.ip = closure.function.chunk.code
  frame.slots = vm.stackTop - argCount - 1

  return true

proc callValue(vm: var VM, callee: Value, argCount: int32): bool =
  if isObj(callee):
    case objType(callee)
    of ObjtBoundMethod:
      let bound = asBoundMethod(callee)

      vm.stackTop[-argCount - 1] = bound.receiver
      return call(vm, bound.`method`, argCount)
    of ObjtClass:
      let klass = asClass(callee)

      vm.stackTop[-argCount - 1] = objVal(newInstance(vm, klass))

      var initializer: Value

      if tableGet(klass.methods, vm.initString, initializer):
        return call(vm, asClosure(initializer), argCount)
      elif argCount != 0:
        runtimeError(vm, "Expected 0 arguments but got $1.", argCount)
        return false

      return true
    of ObjtClosure:
      return call(vm, asClosure(callee), argCount)
    of ObjtNative:
      let
        native = asNative(callee)
        res = native(argCount, vm.stackTop - argCount)

      vm.stackTop -= argCount + 1

      push(vm, res)

      return true
    else:
      discard

  runtimeError(vm, "Can only call functions and classes.")

  return false

proc invokeFromClass(vm: var VM, klass: ptr ObjClass, name: ptr ObjString, argCount: int32): bool =
  var `method`: Value

  if not tableGet(klass.methods, name, `method`):
    runtimeError(vm, "Undefined property '$1'.", cast[cstring](name.chars))
    return false

  call(vm, asClosure(`method`), argCount)

proc invoke(vm: var VM, name: ptr ObjString, argCount: int32): bool =
  let receiver = peek(vm, argCount)

  if not isInstance(receiver):
    runtimeError(vm, "Only instances have methods.")
    return false

  let instance = asInstance(receiver)

  var value: Value

  if tableGet(instance.fields, name, value):
    vm.stackTop[-argCount - 1] = value
    return callValue(vm, value, argCount)

  invokeFromClass(vm, instance.klass, name, argCount)

proc bindMethod(vm: var VM, klass: ptr ObjClass, name: ptr ObjString): bool =
  var `method`: Value

  if not tableGet(klass.methods, name, `method`):
    runtimeError(vm, "Undefined property '$1'.", cast[cstring](name.chars))
    return false

  let bound = newBoundMethod(vm, peek(vm, 0), asClosure(`method`))

  discard pop(vm)

  push(vm, objVal(bound))

  true

proc captureUpvalue(vm: var VM, local: ptr Value): ptr ObjUpvalue =
  var
    prevUpvalue: ptr ObjUpvalue = nil
    upvalue = vm.openUpvalues

  while not(isNil(upvalue)) and upvalue.location > local:
    prevUpvalue = upvalue
    upvalue = upvalue.next

  if not(isNil(upvalue)) and upvalue.location == local:
    return upvalue

  result = newUpvalue(vm, local)

  result.next = upvalue

  if isNil(prevUpvalue):
    vm.openUpvalues = result
  else:
    prevUpvalue.next = result

proc closeUpvalues(vm: var VM, last: ptr Value) =
  while not(isNil(vm.openUpvalues)) and vm.openUpvalues.location >= last:
    var upvalue = vm.openUpvalues

    upvalue.closed = upvalue.location[]
    upvalue.location = addr upvalue.closed

    vm.openUpvalues = upvalue.next

proc defineMethod(vm: var VM, name: ptr ObjString) =
  let
    `method` = peek(vm, 0)
    klass = asClass(peek(vm, 1))

  discard tableSet(vm, klass.methods, name, `method`)

  discard pop(vm)

proc isFalsey(value: Value): bool =
  isNil(value) or (isBool(value) and not(asBool(value)))

proc concatenate(vm: var VM) =
  let
    b = asString(peek(vm, 0))
    a = asString(peek(vm, 1))
    length = a.length + b.length
    chars = allocate(vm, char, length + 1)

  copyMem(chars, a.chars, a.length)
  copyMem(chars + a.length, b.chars, b.length)

  chars[length] = '\0'

  var result = takeString(vm, chars, length)

  discard pop(vm)
  discard pop(vm)

  push(vm, objVal(result))

template readByte(): uint8 =
  let tmp = frame.ip[]
  frame.ip += 1
  tmp

template readShort(): uint16 =
  var tmp = uint16(frame.ip[]) shl 8

  frame.ip += 1
  tmp = tmp or uint16(frame.ip[])
  frame.ip += 1

  tmp

template readConstant(): Value =
  frame.closure.function.chunk.constants.values[readByte()]

template readString(): ptr ObjString =
  asString(readConstant())

template binaryOp(valueType: untyped, op: untyped) =
  if not(isNumber(peek(vm, 0))) or not(isNumber(peek(vm, 1))):
    runtimeError(vm, "Operands must be numbers.")
    return InterpretRuntimeError

  let
    b = asNumber(pop(vm))
    a = asNumber(pop(vm))

  push(vm, valueType(op(a, b)))

proc run(vm: var VM): InterpretResult =
  var frame = addr vm.frames[vm.frameCount - 1]

  while true:
    when defined(debugTraceExecution):
      write(stdout, "          ")

      for slot in cast[ptr Value](addr vm.stack[0]) ..< vm.stackTop:
        write(stdout, "[ ")
        printValue(slot[])
        write(stdout, " ]")

      write(stdout, '\n')

      discard disassembleInstruction(frame.closure.function.chunk, int32(frame.ip - frame.closure.function.chunk.code))

    let instruction = readByte()

    case instruction
    of uint8(OpConstant):
      let constant = readConstant()
      push(vm, constant)
    of uint8(OpNil):
      push(vm, nilVal)
    of uint8(OpTrue):
      push(vm, boolVal(true))
    of uint8(OpFalse):
      push(vm, boolVal(false))
    of uint8(OpPop):
      discard pop(vm)
    of uint8(OpGetLocal):
      let slot = readByte()
      push(vm, frame.slots[slot])
    of uint8(OpSetLocal):
      let slot = readByte()
      frame.slots[slot] = peek(vm, 0)
    of uint8(OpGetGlobal):
      let name = readString()

      var value: Value

      if not tableGet(vm.globals, name, value):
        runtimeError(vm, "Undefined variable '$1'.", cast[cstring](name.chars))
        return InterpretRuntimeError

      push(vm, value)
    of uint8(OpDefineGlobal):
      let name = readString()

      discard tableSet(vm, vm.globals, name, peek(vm, 0))
      discard pop(vm)
    of uint8(OpSetGlobal):
      let name = readString()

      if tableSet(vm, vm.globals, name, peek(vm, 0)):
        discard tableDelete(vm.globals, name)

        runtimeError(vm, "Undefined variable '$1'.", cast[cstring](name.chars))
        return InterpretRuntimeError
    of uint8(OpGetUpvalue):
      let slot = readByte()

      push(vm, frame.closure.upvalues[slot].location[])
    of uint8(OpSetUpvalue):
      let slot = readByte()

      frame.closure.upvalues[slot].location[] = peek(vm, 0)
    of uint8(OpGetProperty):
      if not isInstance(peek(vm, 0)):
        runtimeError(vm, "Only instances have properties.")
        return InterpretRuntimeError

      let
        instance = asInstance(peek(vm, 0))
        name = readString()

      var value: Value

      if tableGet(instance.fields, name, value):
        discard pop(vm)

        push(vm, value)
      elif not bindMethod(vm, instance.klass, name):
        return InterpretRuntimeError
    of uint8(OpSetProperty):
      if not isInstance(peek(vm, 1)):
        runtimeError(vm, "Only instances have fields.")
        return InterpretRuntimeError

      let instance = asInstance(peek(vm, 1))

      discard tableSet(vm, instance.fields, readString(), peek(vm, 0))

      let value = pop(vm)

      discard pop(vm)

      push(vm, value)
    of uint8(OpGetSuper):
      let
        name = readString()
        superclass = asClass(pop(vm))

      if not bindMethod(vm, superclass, name):
        return InterpretRuntimeError
    of uint8(OpEqual):
      let
        b = pop(vm)
        a = pop(vm)

      push(vm, boolVal(valuesEqual(a, b)))
    of uint8(OpGreater):
      binaryOp(boolVal, `>`)
    of uint8(OpLess):
      binaryOp(boolVal, `<`)
    of uint8(OpAdd):
      if isString(peek(vm, 0)) and isString(peek(vm, 1)):
        concatenate(vm)
      elif isNumber(peek(vm, 0)) and isNumber(peek(vm, 1)):
        let
          b = asNumber(pop(vm))
          a = asNumber(pop(vm))

        push(vm, numberVal(a + b))
      else:
        runtimeError(vm, "Operands must be two numbers or two strings.")
        return InterpretRuntimeError
    of uint8(OpSubtract):
      binaryOp(numberVal, `-`)
    of uint8(OpMultiply):
      binaryOp(numberVal, `*`)
    of uint8(OpDivide):
      binaryOp(numberVal, `/`)
    of uint8(OpNot):
      push(vm, boolVal(isFalsey(pop(vm))))
    of uint8(OpNegate):
      if not isNumber(peek(vm, 0)):
        runtimeError(vm, "Operand must be a number.")
        return InterpretRuntimeError

      push(vm, numberVal(-asNumber(pop(vm))))
    of uint8(OpPrint):
      printValue(pop(vm))
      write(stdout, '\n')
    of uint8(OpJump):
      let offset = readShort()

      frame.ip += offset
    of uint8(OpJumpIfFalse):
      let offset = readShort()

      if isFalsey(peek(vm, 0)):
        frame.ip += offset
    of uint8(OpLoop):
      let offset = readShort()
      frame.ip -= offset
    of uint8(OpCall):
      let argCount = readByte().int32

      if not callValue(vm, peek(vm, argCount), argCount):
        return InterpretRuntimeError

      frame = addr vm.frames[vm.frameCount - 1]
    of uint8(OpInvoke):
      let
        `method` = readString()
        argCount = readByte().int32

      if not invoke(vm, `method`, argCount):
        return InterpretRuntimeError

      frame = addr vm.frames[vm.frameCount - 1]
    of uint8(OpSuperInvoke):
      let
        `method` = readString()
        argCount = readByte().int32
        superclass = asClass(pop(vm))

      if not invokeFromClass(vm, superclass, `method`, argCount):
        return InterpretRuntimeError

      frame = addr vm.frames[vm.frameCount - 1]
    of uint8(OpClosure):
      let function = asFunction(readConstant())

      var closure = newClosure(vm, function)

      push(vm, objVal(closure))

      for i in 0 ..< closure.upvalueCount:
        let
          isLocal = readByte()
          index = readByte()

        if bool(isLocal):
          closure.upvalues[i] = captureUpvalue(vm, frame.slots + index)
        else:
          closure.upvalues[i] = frame.closure.upvalues[index]
    of uint8(OpCloseUpvalue):
      closeUpvalues(vm, vm.stackTop - 1)

      discard pop(vm)
    of uint8(OpReturn):
      let res = pop(vm)

      closeUpvalues(vm, frame.slots)

      dec(vm.frameCount)

      if vm.frameCount == 0:
        discard pop(vm)
        return InterpretOk

      vm.stackTop = frame.slots

      push(vm, res)

      frame = addr vm.frames[vm.frameCount - 1]
    of uint8(OpClass):
      push(vm, objVal(newClass(vm, readString())))
    of uint8(OpInherit):
      var superclass = peek(vm, 1)

      if not isClass(superclass):
        runtimeError(vm, "Superclass must be a class.")
        return InterpretRuntimeError

      var subclass = asClass(peek(vm, 0))

      tableAddAll(vm, asClass(superclass).methods, subclass.methods)

      discard pop(vm)
    of uint8(OpMethod):
      defineMethod(vm, readString())
    else:
      discard

proc interpret*(vm: var VM, source: var string): InterpretResult =
  let function = compile(vm, source)

  if isNil(function):
    return InterpretCompileError

  push(vm, objVal(function))

  let closure = newClosure(vm, function)

  discard pop(vm)

  push(vm, objVal(closure))

  discard call(vm, closure, 0)

  run(vm)
