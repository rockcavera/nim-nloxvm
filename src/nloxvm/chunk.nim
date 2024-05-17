import ./memory, ./value, ./types

import ./private/pointer_arithmetics

proc initChunk*(chunk: var Chunk) =
  chunk.count = 0
  chunk.capacity = 0
  chunk.code = nil
  chunk.lines = nil

  initValueArray(chunk.constants)

proc freeChunk*(chunk: var Chunk) {.exportc: "freeChunk__nloxvmZchunk_u23".} =
  freeArray(uint8, chunk.code, chunk.capacity)
  freeArray(int32, chunk.lines, chunk.capacity)
  freeValueArray(chunk.constants)
  initChunk(chunk)

proc writeChunk*(chunk: var Chunk, `byte`: uint8, line: int32) =
  if chunk.capacity < (chunk.count + 1):
    let oldCapacity = chunk.capacity

    chunk.capacity = growCapacity(oldCapacity)
    chunk.code = growArray(uint8, chunk.code, oldCapacity, chunk.capacity)
    chunk.lines = growArray(int32, chunk.lines, oldCapacity, chunk.capacity)

  chunk.code[chunk.count] = `byte`
  chunk.lines[chunk.count] = line
  chunk.count += 1

template writeChunk*(chunk: var Chunk, opCode: OpCode, line: int32) =
  writeChunk(chunk, uint8(opCode), line)

template writeChunk*(chunk: var Chunk, value: int32, line: int32) =
  writeChunk(chunk, uint8(value), line)

proc push(value: Value) {.importc: "push__nloxvmZvm95impl_u4".}
proc pop(): Value {.importc: "pop__nloxvmZvm95impl_u15".}

proc addConstant*(chunk: var Chunk, value: Value): int32 =
  push(value)

  writeValueArray(chunk.constants, value)

  discard pop()
  return chunk.constants.count - 1
