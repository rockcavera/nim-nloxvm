import std/[strutils, times]

import ./compiler, ./globals, ./memory, ./object, ./object_helpers, ./printer, ./table, ./types, ./value, ./value_helpers

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

proc resetStack() =
  vm.stackTop = addr vm.stack[0]
  vm.frameCount = 0
  vm.openUpvalues = nil

proc runtimeError(format: string, args: varargs[string, `$`]) =
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

  resetStack()

proc push(value: Value) {.extern: "push__nloxvmZvm95impl_u4".}
proc pop(): Value {.extern: "pop__nloxvmZvm95impl_u15".}

proc defineNative(name: cstring, function: NativeFn) =
  push(objVal(copyString(cast[ptr char](name), len(name).int32)))
  push(objVal(newNative(function)))

  discard tableSet(vm.globals, asString(vm.stack[0]), vm.stack[1])

  discard pop()
  discard pop()

proc initVM*() =
  resetStack()

  vm.objects = nil
  vm.bytesAllocated = 0
  vm.nextGC = 1024 * 1024

  vm.grayCount = 0
  vm.grayCapacity = 0
  vm.grayStack = nil

  initTable(vm.globals)
  initTable(vm.strings)

  vm.initString = nil
  vm.initString = copyString(cast[ptr char](cstring"init"), 4)

  defineNative(cstring"clock", clockNative)

proc freeVM*() =
  freeTable(vm.globals)
  freeTable(vm.strings)

  vm.initString = nil

  freeObjects()

proc push(value: Value) =
  vm.stackTop[] = value
  vm.stackTop += 1

proc pop(): Value =
  vm.stackTop -= 1
  return vm.stackTop[]

proc peek(distance: int32): Value =
  vm.stackTop[-1 - distance]

proc call(closure: ptr ObjClosure, argCount: int32): bool =
  if argCount != closure.function.arity:
    runtimeError("Expected $1 arguments but got $2.", closure.function.arity, argCount)
    return false

  if vm.frameCount == framesMax:
    runtimeError("Stack overflow.")
    return false

  var frame = addr vm.frames[vm.frameCount]

  inc(vm.frameCount)

  frame.closure = closure
  frame.ip = closure.function.chunk.code
  frame.slots = vm.stackTop - argCount - 1

  return true

proc callValue(callee: Value, argCount: int32): bool =
  if isObj(callee):
    case objType(callee)
    of ObjtBoundMethod:
      let bound = asBoundMethod(callee)

      vm.stackTop[-argCount - 1] = bound.receiver
      return call(bound.`method`, argCount)
    of ObjtClass:
      let klass = asClass(callee)

      vm.stackTop[-argCount - 1] = objVal(newInstance(klass))

      var initializer: Value

      if tableGet(klass.methods, vm.initString, initializer):
        return call(asClosure(initializer), argCount)
      elif argCount != 0:
        runtimeError("Expected 0 arguments but got $1.", argCount)
        return false

      return true
    of ObjtClosure:
      return call(asClosure(callee), argCount)
    of ObjtNative:
      let
        native = asNative(callee)
        res = native(argCount, vm.stackTop - argCount)

      vm.stackTop -= argCount + 1

      push(res)

      return true
    else:
      discard

  runtimeError("Can only call functions and classes.")

  return false

proc invokeFromClass(klass: ptr ObjClass, name: ptr ObjString, argCount: int32): bool =
  var `method`: Value

  if not tableGet(klass.methods, name, `method`):
    runtimeError("Undefined property '$1'.", cast[cstring](name.chars))
    return false

  call(asClosure(`method`), argCount)

proc invoke(name: ptr ObjString, argCount: int32): bool =
  let receiver = peek(argCount)

  if not isInstance(receiver):
    runtimeError("Only instances have methods.")
    return false

  let instance = asInstance(receiver)

  var value: Value

  if tableGet(instance.fields, name, value):
    vm.stackTop[-argCount - 1] = value
    return callValue(value, argCount)

  invokeFromClass(instance.klass, name, argCount)

proc bindMethod(klass: ptr ObjClass, name: ptr ObjString): bool =
  var `method`: Value

  if not tableGet(klass.methods, name, `method`):
    runtimeError("Undefined property '$1'.", cast[cstring](name.chars))
    return false

  let bound = newBoundMethod(peek(0), asClosure(`method`))

  discard pop()

  push(objVal(bound))

  true

proc captureUpvalue(local: ptr Value): ptr ObjUpvalue =
  var
    prevUpvalue: ptr ObjUpvalue = nil
    upvalue = vm.openUpvalues

  while not(isNil(upvalue)) and upvalue.location > local:
    prevUpvalue = upvalue
    upvalue = upvalue.next

  if not(isNil(upvalue)) and upvalue.location == local:
    return upvalue

  result = newUpvalue(local)

  result.next = upvalue

  if isNil(prevUpvalue):
    vm.openUpvalues = result
  else:
    prevUpvalue.next = result

proc closeUpvalues(last: ptr Value) =
  while not(isNil(vm.openUpvalues)) and vm.openUpvalues.location >= last:
    var upvalue = vm.openUpvalues

    upvalue.closed = upvalue.location[]
    upvalue.location = addr upvalue.closed

    vm.openUpvalues = upvalue.next

proc defineMethod(name: ptr ObjString) =
  let
    `method` = peek(0)
    klass = asClass(peek(1))

  discard tableSet(klass.methods, name, `method`)

  discard pop()

proc isFalsey(value: Value): bool =
  isNil(value) or (isBool(value) and not(asBool(value)))

proc concatenate() =
  let
    b = asString(peek(0))
    a = asString(peek(1))
    length = a.length + b.length
    chars = allocate(char, length + 1)

  copyMem(chars, a.chars, a.length)
  copyMem(chars + a.length, b.chars, b.length)

  chars[length] = '\0'

  var result = takeString(chars, length)

  discard pop()
  discard pop()

  push(objVal(result))

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
  if not(isNumber(peek(0))) or not(isNumber(peek(1))):
    runtimeError("Operands must be numbers.")
    return InterpretRuntimeError

  let
    b = asNumber(pop())
    a = asNumber(pop())

  push(valueType(op(a, b)))

proc run(): InterpretResult =
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
      push(constant)
    of uint8(OpNil):
      push(nilVal)
    of uint8(OpTrue):
      push(boolVal(true))
    of uint8(OpFalse):
      push(boolVal(false))
    of uint8(OpPop):
      discard pop()
    of uint8(OpGetLocal):
      let slot = readByte()
      push(frame.slots[slot])
    of uint8(OpSetLocal):
      let slot = readByte()
      frame.slots[slot] = peek(0)
    of uint8(OpGetGlobal):
      let name = readString()

      var value: Value

      if not tableGet(vm.globals, name, value):
        runtimeError("Undefined variable '$1'.", cast[cstring](name.chars))
        return InterpretRuntimeError

      push(value)
    of uint8(OpDefineGlobal):
      let name = readString()

      discard tableSet(vm.globals, name, peek(0))
      discard pop()
    of uint8(OpSetGlobal):
      let name = readString()

      if tableSet(vm.globals, name, peek(0)):
        discard tableDelete(vm.globals, name)

        runtimeError("Undefined variable '$1'.", cast[cstring](name.chars))
        return InterpretRuntimeError
    of uint8(OpGetUpvalue):
      let slot = readByte()

      push(frame.closure.upvalues[slot].location[])
    of uint8(OpSetUpvalue):
      let slot = readByte()

      frame.closure.upvalues[slot].location[] = peek(0)
    of uint8(OpGetProperty):
      if not isInstance(peek(0)):
        runtimeError("Only instances have properties.")
        return InterpretRuntimeError

      let
        instance = asInstance(peek(0))
        name = readString()

      var value: Value

      if tableGet(instance.fields, name, value):
        discard pop()

        push(value)
      elif not bindMethod(instance.klass, name):
        return InterpretRuntimeError
    of uint8(OpSetProperty):
      if not isInstance(peek(1)):
        runtimeError("Only instances have fields.")
        return InterpretRuntimeError

      let instance = asInstance(peek(1))

      discard tableSet(instance.fields, readString(), peek(0))

      let value = pop()

      discard pop()

      push(value)
    of uint8(OpGetSuper):
      let
        name = readString()
        superclass = asClass(pop())

      if not bindMethod(superclass, name):
        return InterpretRuntimeError
    of uint8(OpEqual):
      let
        b = pop()
        a = pop()

      push(boolVal(valuesEqual(a, b)))
    of uint8(OpGreater):
      binaryOp(boolVal, `>`)
    of uint8(OpLess):
      binaryOp(boolVal, `<`)
    of uint8(OpAdd):
      if isString(peek(0)) and isString(peek(1)):
        concatenate()
      elif isNumber(peek(0)) and isNumber(peek(1)):
        let
          b = asNumber(pop())
          a = asNumber(pop())

        push(numberVal(a + b))
      else:
        runtimeError("Operands must be two numbers or two strings.")
        return InterpretRuntimeError
    of uint8(OpSubtract):
      binaryOp(numberVal, `-`)
    of uint8(OpMultiply):
      binaryOp(numberVal, `*`)
    of uint8(OpDivide):
      binaryOp(numberVal, `/`)
    of uint8(OpNot):
      push(boolVal(isFalsey(pop())))
    of uint8(OpNegate):
      if not isNumber(peek(0)):
        runtimeError("Operand must be a number.")
        return InterpretRuntimeError

      push(numberVal(-asNumber(pop())))
    of uint8(OpPrint):
      printValue(pop())
      write(stdout, '\n')
    of uint8(OpJump):
      let offset = readShort()

      frame.ip += offset
    of uint8(OpJumpIfFalse):
      let offset = readShort()

      if isFalsey(peek(0)):
        frame.ip += offset
    of uint8(OpLoop):
      let offset = readShort()
      frame.ip -= offset
    of uint8(OpCall):
      let argCount = readByte().int32

      if not callValue(peek(argCount), argCount):
        return InterpretRuntimeError

      frame = addr vm.frames[vm.frameCount - 1]
    of uint8(OpInvoke):
      let
        `method` = readString()
        argCount = readByte().int32

      if not invoke(`method`, argCount):
        return InterpretRuntimeError

      frame = addr vm.frames[vm.frameCount - 1]
    of uint8(OpSuperInvoke):
      let
        `method` = readString()
        argCount = readByte().int32
        superclass = asClass(pop())

      if not invokeFromClass(superclass, `method`, argCount):
        return InterpretRuntimeError

      frame = addr vm.frames[vm.frameCount - 1]
    of uint8(OpClosure):
      let function = asFunction(readConstant())

      var closure = newClosure(function)

      push(objVal(closure))

      for i in 0 ..< closure.upvalueCount:
        let
          isLocal = readByte()
          index = readByte()

        if bool(isLocal):
          closure.upvalues[i] = captureUpvalue(frame.slots + index)
        else:
          closure.upvalues[i] = frame.closure.upvalues[index]
    of uint8(OpCloseUpvalue):
      closeUpvalues(vm.stackTop - 1)

      discard pop()
    of uint8(OpReturn):
      let res = pop()

      closeUpvalues(frame.slots)

      dec(vm.frameCount)

      if vm.frameCount == 0:
        discard pop()
        return InterpretOk

      vm.stackTop = frame.slots

      push(res)

      frame = addr vm.frames[vm.frameCount - 1]
    of uint8(OpClass):
      push(objVal(newClass(readString())))
    of uint8(OpInherit):
      var superclass = peek(1)

      if not isClass(superclass):
        runtimeError("Superclass must be a class.")
        return InterpretRuntimeError

      var subclass = asClass(peek(0))

      tableAddAll(asClass(superclass).methods, subclass.methods)

      discard pop()
    of uint8(OpMethod):
      defineMethod(readString())
    else:
      discard

proc interpret*(source: var string): InterpretResult =
  let function = compile(source)

  if isNil(function):
    return InterpretCompileError

  push(objVal(function))

  let closure = newClosure(function)

  discard pop()

  push(objVal(closure))

  discard call(closure, 0)

  run()
