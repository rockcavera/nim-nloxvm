import ./chunk, ./debug

proc main*(argc: int, argv: openArray[string]): int =
  var chunk: Chunk

  initChunk(chunk)

  let constant = addConstant(chunk, 1.2)

  writeChunk(chunk, OP_CONSTANT, 123)
  writeChunk(chunk, constant, 123)

  writeChunk(chunk, OP_RETURN, 123)

  disassembleChunk(chunk, "test chunk")

  freeChunk(chunk)

  return 0
