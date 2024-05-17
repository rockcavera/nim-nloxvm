import std/strformat

import ./object_helpers, ./printer, ./types

import ./private/pointer_arithmetics

proc disassembleInstruction*(chunk: var Chunk, offset: int32): int32

proc disassembleChunk*(chunk: var Chunk, name: ptr char) =
  write(stdout, fmt"== {cast[cstring](name)} =={'\n'}")

  var offset = 0'i32

  while offset < chunk.count:
    offset = disassembleInstruction(chunk, offset)

proc constantInstruction(name: string, chunk: var Chunk, offset: int32): int32 =
  let constant = chunk.code[offset + 1]

  write(stdout, fmt"{name: <16} {constant: >4} '")

  printValue(chunk.constants.values[constant])

  write(stdout, "'\n")

  offset + 2

proc invokeInstruction(name: string, chunk: var Chunk, offset: int32): int32 =
  let
    constant = chunk.code[offset + 1]
    argCount = chunk.code[offset + 2]

  write(stdout, fmt"{name: <16}  ({argCount} args) {constant: >4} '")

  printValue(chunk.constants.values[constant])

  write(stdout, "'\n")

  offset + 3

proc simpleInstruction(name: string, offset: int32): int32 =
  write(stdout, fmt"{name}{'\n'}")

  offset + 1

proc byteInstruction(name: string, chunk: var Chunk, offset: int32): int32 =
  let slot = chunk.code[offset + 1]

  write(stdout, fmt"{name: <16} {slot: >4}{'\n'}")

  offset + 2

proc jumpInstruction(name: string, sign: int32, chunk: var Chunk, offset: int32): int32 =
  var jump = uint16(chunk.code[offset + 1]) shl 8

  jump = jump or uint8(chunk.code[offset + 2])

  let offset2 = offset + 3 + sign * int32(jump)

  write(stdout, fmt"{name: <16} {offset: >4} -> {offset2}{'\n'}")

  offset + 3

proc disassembleInstruction*(chunk: var Chunk, offset: int32): int32 =
  write(stdout, fmt"{offset:04} ")

  if offset > 0 and chunk.lines[offset] == chunk.lines[offset - 1]:
    write(stdout, "   | ")
  else:
    write(stdout, fmt"{chunk.lines[offset]: >4} ")

  let instruction = chunk.code[offset]

  case instruction
  of uint8(OpConstant):
    return constantInstruction("OpConstant", chunk, offset)
  of uint8(OpNil):
    return simpleInstruction("OpNil", offset)
  of uint8(OpTrue):
    return simpleInstruction("OpTrue", offset)
  of uint8(OpFalse):
    return simpleInstruction("OpFalse", offset)
  of uint8(OpPop):
    return simpleInstruction("OpPop", offset)
  of uint8(OpGetLocal):
    return byteInstruction("OpGetLocal", chunk, offset)
  of uint8(OpSetLocal):
    return byteInstruction("OpSetLocal", chunk, offset)
  of uint8(OpGetGlobal):
    return constantInstruction("OpGetGlobal", chunk, offset)
  of uint8(OpDefineGlobal):
    return constantInstruction("OpDefineGlobal", chunk, offset)
  of uint8(OpSetGlobal):
    return constantInstruction("OpSetGlobal", chunk, offset)
  of uint8(OpGetUpvalue):
    return byteInstruction("OpGetUpvalue", chunk, offset)
  of uint8(OpSetUpvalue):
    return byteInstruction("OpSetUpvalue", chunk, offset)
  of uint8(OpGetProperty):
    return constantInstruction("OpGetProperty", chunk, offset)
  of uint8(OpSetProperty):
    return constantInstruction("OpSetProperty", chunk, offset)
  of uint8(OpGetSuper):
    return constantInstruction("OpGetSuper", chunk, offset)
  of uint8(OpEqual):
    return simpleInstruction("OpEqual", offset)
  of uint8(OpGreater):
    return simpleInstruction("OpGreater", offset)
  of uint8(OpLess):
    return simpleInstruction("OpLess", offset)
  of uint8(OpAdd):
    return simpleInstruction("OpAdd", offset)
  of uint8(OpSubtract):
    return simpleInstruction("OpSubtract", offset)
  of uint8(OpMultiply):
    return simpleInstruction("OpMultiply", offset)
  of uint8(OpDivide):
    return simpleInstruction("OpDivide", offset)
  of uint8(OpNot):
    return simpleInstruction("OpNot", offset)
  of uint8(OpNegate):
    return simpleInstruction("OpNegate", offset)
  of uint8(OpPrint):
    return simpleInstruction("OpPrint", offset)
  of uint8(OpJump):
    return jumpInstruction("OpJump", 1, chunk, offset)
  of uint8(OpJumpIfFalse):
    return jumpInstruction("OpJumpIfFalse", 1, chunk, offset)
  of uint8(OpLoop):
    return jumpInstruction("OpLoop", -1, chunk, offset)
  of uint8(OpCall):
    return byteInstruction("OpCall", chunk, offset)
  of uint8(OpInvoke):
    return invokeInstruction("OpInvoke", chunk, offset)
  of uint8(OpSuperInvoke):
    return invokeInstruction("OpSuperInvoke", chunk, offset)
  of uint8(OpClosure):
    var offset = offset + 1

    let constant = chunk.code[offset]

    inc(offset)

    write(stdout, fmt"""{"OpClosure": <16} {constant: >4} """)

    printValue(chunk.constants.values[constant])

    write(stdout, '\n')

    let function = asFunction(chunk.constants.values[constant])

    for j in 0 ..< function.upvalueCount:
      let isLocal = chunk.code[offset]

      inc(offset)

      let index = chunk.code[offset]

      inc(offset)

      let isLocalStr = if bool(isLocal): "local" else: "upvalue"

      write(stdout, fmt"{offset - 2:04}      |                     {isLocalStr} {index}{'\n'}")
    return offset
  of uint8(OpCloseUpvalue):
    return simpleInstruction("OpCloseUpvalue", offset)
  of uint8(OpReturn):
    return simpleInstruction("OpReturn", offset)
  of uint8(OpClass):
    return constantInstruction("OpClass", chunk, offset)
  of uint8(OpInherit):
    return simpleInstruction("OpInherit", offset)
  of uint8(OpMethod):
    return constantInstruction("OpMethod", chunk, offset)
  else:
    write(stdout, fmt"Unknown opcode {instruction}{'\n'}")
    return offset + 1
