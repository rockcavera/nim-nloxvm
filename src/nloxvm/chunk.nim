import ./memory, ./value

import ./private/pointer_arithmetics

type
  OpCode* {.size: 1.} = enum
    OP_CONSTANT,
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,
    OP_NEGATE,
    OP_RETURN

  Chunk* = object
    count*: int32
    capacity: int32
    code*: ptr uint8
    lines*: ptr int32
    constants*: ValueArray

proc initChunk*(chunk: var Chunk) =
  chunk.count = 0
  chunk.capacity = 0
  chunk.code = nil
  chunk.lines = nil

  initValueArray(chunk.constants)

proc freeChunk*(chunk: var Chunk) =
  free_array(uint8, chunk.code, chunk.capacity)
  free_array(int32, chunk.lines, chunk.capacity)
  freeValueArray(chunk.constants)
  initChunk(chunk)

proc writeChunk*(chunk: var Chunk, `byte`: uint8, line: int32) =
  if chunk.capacity < (chunk.count + 1):
    let oldCapacity = chunk.capacity

    chunk.capacity = grow_capacity(oldCapacity)
    chunk.code = grow_array(uint8, chunk.code, oldCapacity, chunk.capacity)
    chunk.lines = grow_array(int32, chunk.lines, oldCapacity, chunk.capacity)

  chunk.code[chunk.count] = `byte`
  chunk.lines[chunk.count] = line
  chunk.count += 1

template writeChunk*(chunk: var Chunk, opCode: OpCode, line: int32) =
  writeChunk(chunk, uint8(opCode), line)

template writeChunk*(chunk: var Chunk, value: int32, line: int32) =
  writeChunk(chunk, uint8(value), line)

proc addConstant*(chunk: var Chunk, value: Value): int32 =
  writeValueArray(chunk.constants, value)
  return chunk.constants.count - 1
