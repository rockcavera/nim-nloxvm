import std/[strformat, strutils, times]

import ./compiler, ./globals, ./memory, ./object, ./printer, ./table, ./types, ./value

when defined(DEBUG_TRACE_EXECUTION):
  import ./debug

import ./private/pointer_arithmetics

proc push(value: Value)
proc pop(): Value

proc clockNative(argCount: int32, args: ptr Value): Value =
  numberVal(cpuTime())

proc resetStack() =
  vm.stackTop = cast[ptr Value](addr vm.stack[0])
  vm.frameCount = 0

proc runtimeError(format: string, args: varargs[string, `$`]) =
  if len(args) > 0:
    write(stderr, format % args, "\n")
  else:
    write(stderr, format, "\n")

  for i in countdown(vm.frameCount - 1, 0):
    let
      frame = cast[ptr CallFrame](addr vm.frames[i])
      function = frame.function
      instruction = frame.ip - function.chunk.code - 1

    write(stderr, "[line $1] in " % $function.chunk.lines[instruction])

    if isNil(function.name):
      write(stderr, "script\n")
    else:
      write(stderr, fmt"{cast[cstring](function.name.chars)}(){'\n'}")

  resetStack()

proc defineNative(name: cstring, function: NativeFn) =
  push(objVal(cast[ptr Obj](copyString(cast[ptr char](name), len(name).int32))))
  push(objVal(cast[ptr Obj](newNative(function))))

  discard tableSet(vm.globals, asString(vm.stack[0]), vm.stack[1])

  discard pop()
  discard pop()

proc initVM*() =
  resetStack()

  vm.objects = nil

  initTable(vm.globals)
  initTable(vm.strings)

  defineNative(cstring"clock", clockNative)

proc freeVM*() =
  freeTable(vm.globals)
  freeTable(vm.strings)

  freeObjects()

proc push(value: Value) =
  vm.stackTop[] = value
  vm.stackTop += 1

proc pop(): Value =
  vm.stackTop -= 1
  return vm.stackTop[]

proc peek(distance: int32): Value =
  vm.stackTop[-1 - distance]

proc call(function: ptr ObjFunction, argCount: int32): bool =
  if argCount != function.arity:
    runtimeError("Expected $1 arguments but got $2.", function.arity, argCount)
    return false

  if vm.frameCount == FRAMES_MAX:
    runtimeError("Stack overflow.")
    return false

  var frame = cast[ptr CallFrame](addr vm.frames[vm.frameCount])

  inc(vm.frameCount)

  frame.function = function
  frame.ip = function.chunk.code
  frame.slots = vm.stackTop - argCount - 1

  return true

proc callValue(callee: Value, argCount: int32): bool =
  if isObj(callee):
    case objType(callee)
    of OBJT_FUNCTION:
      return call(asFunction(callee), argCount)
    of OBJT_NATIVE:
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

proc isFalsey(value: Value): bool =
  isNil(value) or (isBool(value) and not(asBool(value)))

proc concatenate() =
  let
    b = asString(pop())
    a = asString(pop())
    length = a.length + b.length
    chars = allocate(char, length + 1)

  copyMem(chars, a.chars, a.length)
  copyMem(chars + a.length, b.chars, b.length)

  chars[length] = '\0'

  var result = takeString(chars, length)

  push(objVal(cast[ptr Obj](result)))

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
  frame.function.chunk.constants.values[readByte()]

template readString(): ptr ObjString =
  asString(readConstant())

template binaryOp(valueType: untyped, op: untyped) =
  if not(isNumber(peek(0))) or not(isNumber(peek(1))):
    runtimeError("Operands must be numbers.")
    return INTERPRET_RUNTIME_ERROR

  let
    b = asNumber(pop())
    a = asNumber(pop())

  push(valueType(op(a, b)))

proc run(): InterpretResult =
  var frame = cast[ptr CallFrame](addr vm.frames[vm.frameCount - 1])

  while true:
    when defined(DEBUG_TRACE_EXECUTION):
      write(stdout, "          ")

      for slot in cast[ptr Value](addr vm.stack[0]) ..< vm.stackTop:
        write(stdout, "[ ")
        printValue(slot[])
        write(stdout, " ]")

      write(stdout, '\n')

      discard disassembleInstruction(frame.function.chunk[], int32(frame.ip - frame.function.chunk.code))

    let instruction = readByte()

    case instruction
    of uint8(OP_CONSTANT):
      let constant = readConstant()
      push(constant)
    of uint8(OP_NIL):
      push(nilVal())
    of uint8(OP_TRUE):
      push(boolVal(true))
    of uint8(OP_FALSE):
      push(boolVal(false))
    of uint8(OP_POP):
      discard pop()
    of uint8(OP_GET_LOCAL):
      let slot = readByte()
      push(frame.slots[slot])
    of uint8(OP_SET_LOCAL):
      let slot = readByte()
      frame.slots[slot] = peek(0)
    of uint8(OP_GET_GLOBAL):
      let name = readString()

      var value: Value

      if not tableGet(vm.globals, name, value):
        runtimeError("Undefined variable '$1'.", cast[cstring](name.chars))
        return INTERPRET_RUNTIME_ERROR

      push(value)
    of uint8(OP_DEFINE_GLOBAL):
      let name = readString()

      discard tableSet(vm.globals, name, peek(0))
      discard pop()
    of uint8(OP_SET_GLOBAL):
      let name = readString()

      if tableSet(vm.globals, name, peek(0)):
        discard tableDelete(vm.globals, name)

        runtimeError("Undefined variable '$1'.", cast[cstring](name.chars))
        return INTERPRET_RUNTIME_ERROR
    of uint8(OP_EQUAL):
      let
        b = pop()
        a = pop()

      push(boolVal(valuesEqual(a, b)))
    of uint8(OP_GREATER):
      binaryOp(boolVal, `>`)
    of uint8(OP_LESS):
      binaryOp(boolVal, `<`)
    of uint8(OP_ADD):
      if isString(peek(0)) and isString(peek(1)):
        concatenate()
      elif isNumber(peek(0)) and isNumber(peek(1)):
        let
          b = asNumber(pop())
          a = asNumber(pop())

        push(numberVal(a + b))
      else:
        runtimeError("Operands must be two numbers or two strings.")
        return INTERPRET_RUNTIME_ERROR
    of uint8(OP_SUBTRACT):
      binaryOp(numberVal, `-`)
    of uint8(OP_MULTIPLY):
      binaryOp(numberVal, `*`)
    of uint8(OP_DIVIDE):
      binaryOp(numberVal, `/`)
    of uint8(OP_NOT):
      push(boolVal(isFalsey(pop())))
    of uint8(OP_NEGATE):
      if not isNumber(peek(0)):
        runtimeError("Operand must be a number.")
        return INTERPRET_RUNTIME_ERROR

      push(numberVal(-asNumber(pop())))
    of uint8(OP_PRINT):
      printValue(pop())
      write(stdout, '\n')
    of uint8(OP_JUMP):
      let offset = readShort()

      frame.ip += offset
    of uint8(OP_JUMP_IF_FALSE):
      let offset = readShort()

      if isFalsey(peek(0)):
        frame.ip += offset
    of uint8(OP_LOOP):
      let offset = readShort()
      frame.ip -= offset
    of uint8(OP_CALL):
      let argCount = readByte().int32

      if not callValue(peek(argCount), argCount):
        return INTERPRET_RUNTIME_ERROR

      frame = cast[ptr CallFrame](addr vm.frames[vm.frameCount - 1])
    of uint8(OP_RETURN):
      let res = pop()

      dec(vm.frameCount)

      if vm.frameCount == 0:
        discard pop()
        return INTERPRET_OK

      vm.stackTop = frame.slots

      push(res)

      frame = cast[ptr CallFrame](addr vm.frames[vm.frameCount - 1])
    else:
      discard

proc interpret*(source: var string): InterpretResult =
  let function = compile(source)

  if isNil(function):
    return INTERPRET_COMPILE_ERROR

  push(objVal(cast[ptr Obj](function)))

  discard call(function, 0)

  run()
