import ./memory, ./value, ./types

import ./private/pointer_arithmetics

proc initChunk*(chunk: var Chunk) =
  chunk.count = 0
  chunk.capacity = 0
  chunk.code = nil
  chunk.lines = nil

  initValueArray(chunk.constants)

proc freeChunk*(vm: var VM, chunk: var Chunk) {.exportc: "freeChunk__nloxvmZchunk_u23".} =
  freeArray(vm, uint8, chunk.code, chunk.capacity)
  freeArray(vm, int32, chunk.lines, chunk.capacity)
  freeValueArray(vm, chunk.constants)
  initChunk(chunk)

proc writeChunk*(vm: var VM, chunk: var Chunk, `byte`: uint8, line: int32) =
  if chunk.capacity < (chunk.count + 1):
    let oldCapacity = chunk.capacity

    chunk.capacity = growCapacity(oldCapacity)
    chunk.code = growArray(vm, uint8, chunk.code, oldCapacity, chunk.capacity)
    chunk.lines = growArray(vm, int32, chunk.lines, oldCapacity, chunk.capacity)

  chunk.code[chunk.count] = `byte`
  chunk.lines[chunk.count] = line
  chunk.count += 1

template writeChunk*(vm: var VM, chunk: var Chunk, opCode: OpCode, line: int32) =
  writeChunk(vm, chunk, uint8(opCode), line)

template writeChunk*(vm: var VM, chunk: var Chunk, value: int32, line: int32) =
  writeChunk(vm, chunk, uint8(value), line)

proc push(vm: var VM, value: Value) {.importc: "push__nloxvmZvm95impl_u4".}
proc pop(vm: var VM): Value {.importc: "pop__nloxvmZvm95impl_u15".}

proc addConstant*(vm: var VM, chunk: var Chunk, value: Value): int32 =
  push(vm, value)

  writeValueArray(vm, chunk.constants, value)

  discard pop(vm)
  return chunk.constants.count - 1
