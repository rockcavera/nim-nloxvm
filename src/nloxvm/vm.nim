import ./chunk, ./value

when defined(DEBUG_TRACE_EXECUTION):
  import ./debug

const STACK_MAX = 256

type
  VM = object
    chunk: Chunk
    ip: ptr uint8
    stack: array[STACK_MAX, Value]
    stackTop: ptr Value

  InterpretResult* = enum
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR

var vm: VM

proc resetStack() =
  vm.stackTop = cast[ptr Value](addr vm.stack[0])

proc initVM*() =
  resetStack()

proc freeVM*() =
  discard

proc push(value: Value) =
  vm.stackTop[] = value
  vm.stackTop = cast[ptr Value](cast[uint](vm.stackTop) + sizeof(Value).uint)

proc pop(): Value =
  vm.stackTop = cast[ptr Value](cast[uint](vm.stackTop) - sizeof(Value).uint)
  return vm.stackTop[]

template readByte(): uint8 =
  let tmp = vm.ip[]
  vm.ip = cast[ptr uint8](cast[uint](vm.ip) + 1)
  tmp

template readConstant(): Value =
  vm.chunk.constants.values[readByte()]

template binaryOp(op: untyped) =
  let
    b = pop()
    a = pop()

  push(op(a, b))

proc run(): InterpretResult =
  while true:
    when defined(DEBUG_TRACE_EXECUTION):
      write(stdout, "          ")

      for slot in countup(cast[uint](addr vm.stack[0]), cast[uint](vm.stackTop) - sizeof(Value).uint, sizeof(Value).uint):
        write(stdout, "[ ")
        printValue(cast[ptr Value](slot)[])
        write(stdout, " ]")

      write(stdout, '\n')

      discard disassembleInstruction(vm.chunk, cast[int32](vm.ip) - cast[int32](vm.chunk.code))

    let instruction = readByte()

    case instruction
    of uint8(OP_CONSTANT):
      let constant = readConstant()
      push(constant)
      printValue(constant)
      write(stdout, '\n')
    of uint8(OP_NEGATE):
      push(-pop())
    of uint8(OP_ADD):
      binaryOp(`+`)
    of uint8(OP_SUBTRACT):
      binaryOp(`-`)
    of uint8(OP_MULTIPLY):
      binaryOp(`*`)
    of uint8(OP_DIVIDE):
      binaryOp(`/`)
    of uint8(OP_RETURN):
      printValue(pop())
      write(stdout, '\n')
      return INTERPRET_OK
    else:
      discard

proc interpret*(chunk: var Chunk): InterpretResult =
  vm.chunk = chunk
  vm.ip = cast[ptr uint8](vm.chunk.code)

  return run()
