import std/strutils

import ./chunk, ./compiler, ./memory, ./object, ./value

when defined(DEBUG_TRACE_EXECUTION):
  import ./debug

import ./private/pointer_arithmetics

const STACK_MAX = 256

type
  VM = object
    chunk: ptr Chunk
    ip: ptr uint8
    stack: array[STACK_MAX, Value]
    stackTop: ptr Value
    objects*: ptr Obj

  InterpretResult* = enum
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR

var vm*: VM

proc resetStack() =
  vm.stackTop = cast[ptr Value](addr vm.stack[0])

proc runtimeError(format: string, args: varargs[string, `$`]) =
  if len(args) > 0:
    write(stderr, format % args, "\n")
  else:
    write(stderr, format, "\n")

  let
    instruction = vm.ip - vm.chunk.code - 1
    line = vm.chunk.lines[instruction]

  write(stderr, "[line $1] in script\n" % $line)

  resetStack()

proc initVM*() =
  resetStack()

  vm.objects = nil

proc freeVM*() =
  freeObjects()

proc push(value: Value) =
  vm.stackTop[] = value
  vm.stackTop += 1

proc pop(): Value =
  vm.stackTop -= 1
  return vm.stackTop[]

proc peek(distance: int32): Value =
  vm.stackTop[-1 - distance]

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
  let tmp = vm.ip[]
  vm.ip += 1
  tmp

template readConstant(): Value =
  vm.chunk.constants.values[readByte()]

template binaryOp(valueType: untyped, op: untyped) =
  if not(isNumber(peek(0))) or not(isNumber(peek(1))):
    runtimeError("Operands must be numbers.")
    return INTERPRET_RUNTIME_ERROR

  let
    b = asNumber(pop())
    a = asNumber(pop())

  push(valueType(op(a, b)))

proc run(): InterpretResult =
  while true:
    when defined(DEBUG_TRACE_EXECUTION):
      write(stdout, "          ")

      for slot in cast[ptr Value](addr vm.stack[0]) ..< vm.stackTop:
        write(stdout, "[ ")
        printValue(slot[])
        write(stdout, " ]")

      write(stdout, '\n')

      discard disassembleInstruction(vm.chunk[], int32(vm.ip - vm.chunk.code))

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
    of uint8(OP_EQUAL):
      let
        b = pop()
        a = pop()

      push(boolVal(valuesEqual(a, b)))
    of uint8(OP_GREATER):
      binaryOp(boolVal, `>`)
    of uint8(OP_LESS):
      binaryOp(boolVal, `<`)
    of uint8(OP_NEGATE):
      if not isNumber(peek(0)):
        runtimeError("Operand must be a number.")
        return INTERPRET_RUNTIME_ERROR

      push(numberVal(-asNumber(pop())))
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
    of uint8(OP_RETURN):
      printValue(pop())
      write(stdout, '\n')
      return INTERPRET_OK
    else:
      discard

proc interpret*(source: var string): InterpretResult =
  var chunk: Chunk

  initChunk(chunk)

  if not compile(source, chunk):
    freeChunk(chunk)
    return INTERPRET_COMPILE_ERROR

  vm.chunk = addr chunk
  vm.ip = vm.chunk.code

  result = run()

  freeChunk(chunk)
