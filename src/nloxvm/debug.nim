import std/strformat

import ./chunk, ./value

import ./private/pointer_arithmetics

proc simpleInstruction(name: string, offset: int32): int32 =
  write(stdout, fmt"{name}{'\n'}")

  return offset + 1

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
  of uint8(OP_ADD):
    return simpleInstruction("OP_ADD", offset)
  of uint8(OP_SUBTRACT):
    return simpleInstruction("OP_SUBTRACT", offset)
  of uint8(OP_MULTIPLY):
    return simpleInstruction("OP_MULTIPLY", offset)
  of uint8(OP_DIVIDE):
    return simpleInstruction("OP_DIVIDE", offset)
  of uint8(OP_NEGATE):
    return simpleInstruction("OP_NEGATE", offset)
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
