import std/strformat

import ./value, ./types

import ./private/pointer_arithmetics

proc simpleInstruction(name: string, offset: int32): int32 =
  write(stdout, fmt"{name}{'\n'}")

  return offset + 1

proc byteInstruction(name: string, chunk: var Chunk, offset: int32): int32 =
  let slot = chunk.code[offset + 1]

  write(stdout, fmt"{name: <16} {slot: >4}")

  offset + 2

proc constantInstruction(name: string, chunk: var Chunk, offset: int32): int32 =
  let constant = chunk.code[offset + 1]

  write(stdout, fmt"{name: <16} {constant: >4} '")

  printValue(chunk.constants.values[constant])

  write(stdout, "'\n")

  return offset + 2

proc disassembleInstruction*(chunk: var Chunk, offset: int32): int32 =
  write(stdout, fmt"{offset:04} ")

  if offset > 0 and chunk.lines[offset] == chunk.lines[offset - 1]:
    write(stdout, "   | ")
  else:
    write(stdout, fmt"{chunk.lines[offset]: >4} ")

  let instruction = chunk.code[offset]

  case instruction
  of uint8(OP_CONSTANT):
    return constantInstruction("OP_CONSTANT", chunk, offset)
  of uint8(OP_NIL):
    return simpleInstruction("OP_NIL", offset)
  of uint8(OP_TRUE):
    return simpleInstruction("OP_TRUE", offset)
  of uint8(OP_FALSE):
    return simpleInstruction("OP_FALSE", offset)
  of uint8(OP_POP):
    return simpleInstruction("OP_POP", offset)
  of uint8(OP_GET_LOCAL):
    return byteInstruction("OP_GET_LOCAL", chunk, offset)
  of uint8(OP_SET_LOCAL):
    return byteInstruction("OP_SET_LOCAL", chunk, offset)
  of uint8(OP_GET_GLOBAL):
    return constantInstruction("OP_GET_GLOBAL", chunk, offset)
  of uint8(OP_DEFINE_GLOBAL):
    return constantInstruction("OP_DEFINE_GLOBAL", chunk, offset)
  of uint8(OP_SET_GLOBAL):
    return constantInstruction("OP_SET_GLOBAL", chunk, offset)
  of uint8(OP_EQUAL):
    return simpleInstruction("OP_EQUAL", offset)
  of uint8(OP_GREATER):
    return simpleInstruction("OP_GREATER", offset)
  of uint8(OP_LESS):
    return simpleInstruction("OP_LESS", offset)
  of uint8(OP_ADD):
    return simpleInstruction("OP_ADD", offset)
  of uint8(OP_SUBTRACT):
    return simpleInstruction("OP_SUBTRACT", offset)
  of uint8(OP_MULTIPLY):
    return simpleInstruction("OP_MULTIPLY", offset)
  of uint8(OP_DIVIDE):
    return simpleInstruction("OP_DIVIDE", offset)
  of uint8(OP_NOT):
    return simpleInstruction("OP_NOT", offset)
  of uint8(OP_NEGATE):
    return simpleInstruction("OP_NEGATE", offset)
  of uint8(OP_PRINT):
    return simpleInstruction("OP_PRINT", offset)
  of uint8(OP_RETURN):
    return simpleInstruction("OP_RETURN", offset)
  else:
    write(stdout, fmt"Unknown opcode {instruction}{'\n'}")
    return offset + 1

proc disassembleChunk*(chunk: var Chunk, name: string) =
  write(stdout, fmt"== {name} =={'\n'}")

  var offset = 0'i32

  while offset < chunk.count:
    offset = disassembleInstruction(chunk, offset)
