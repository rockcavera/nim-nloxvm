import std/[parseutils, strformat]

import ./chunk, ./common, ./object, ./scanner, ./value, ./types

when defined(DEBUG_PRINT_CODE):
  import ./debug

import ./private/pointer_arithmetics

var
  parser: Parser
  current: ptr Compiler
  compilingChunk: ptr Chunk

template lexeme(token: Token): openArray[char] =
  toOpenArray(cast[cstring](token.start), 0, token.length - 1)

proc currentChunk(): var Chunk =
  compilingChunk[]

proc errorAt(token: var Token, message: ptr char) =
  if parser.panicMode:
    return

  parser.panicMode = true

  write(stderr, fmt"[line {token.line}] Error")

  if token.`type` == TOKEN_EOF:
    write(stderr, fmt" at end")
  elif token.`type` == TOKEN_ERROR:
    discard
  else:
    write(stderr, " at '")
    discard writeBuffer(stderr, token.start, token.length)
    write(stderr, "'")

  write(stderr, fmt": {cast[cstring](message)}{'\n'}")

  parser.hadError = true

proc error(message: ptr char) =
  errorAt(parser.previous, message)

proc error(message: string) =
  errorAt(parser.previous, cast[ptr char](addr message[0]))

proc errorAtCurrent(message: ptr char) =
  errorAt(parser.current, message)

proc advance() =
  parser.previous = parser.current

  while true:
    parser.current = scanToken()

    if parser.current.`type` != TOKEN_ERROR:
      break

    errorAtCurrent(parser.current.start)

proc consume(`type`: TokenType, message: string) =
  if parser.current.`type` == `type`:
    advance()
    return

  errorAtCurrent(cast[ptr char](addr message[0]))

proc check(`type`: TokenType): bool =
  parser.current.`type` == `type`

proc match(`type`: TokenType): bool =
  if not check(`type`):
    return false

  advance()

  true

proc emitByte(`byte`: uint8) =
  writeChunk(currentChunk(), `byte`, parser.previous.line)

template emitByte(opCode: OpCode) =
  emitByte(uint8(opCode))

proc emitBytes(byte1: uint8, byte2: uint8) =
  emitByte(byte1)
  emitByte(byte2)

template emitBytes(opCode1: OpCode, opCode2: OpCode) =
  emitBytes(uint8(opCode1), uint8(opCode2))

template emitBytes(opCode: OpCode, `byte`: uint8) =
  emitBytes(uint8(opCode), `byte`)

proc emitReturn() =
  emitByte(OP_RETURN)

proc makeConstant(value: Value): uint8 =
  const UINT8_MAX = high(uint8).int32

  let constant = addConstant(currentChunk(), value)

  if constant > UINT8_MAX:
    error("Too many constants in one chunk.")
    return 0'u8

  uint8(constant)

proc emitConstant(value: Value) =
  emitBytes(OP_CONSTANT, makeConstant(value))

proc initCompiler(compiler: var Compiler) =
  compiler.localCount = 0
  compiler.scopeDepth = 0
  current = addr compiler

proc endCompiler() =
  emitReturn()

  when defined(DEBUG_PRINT_CODE):
    if not parser.hadError:
      disassembleChunk(currentChunk(), "code")

proc beginScope() =
  inc(current.scopeDepth)

proc endScope() =
  dec(current.scopeDepth)

  while (current.localCount > 0) and (current.locals[current.localCount - 1].depth > current.scopeDepth):
    emitByte(OP_POP)

    dec(current.localCount)

proc expression()
proc statement()
proc declaration()
proc getRule(`type`: TokenType): ptr ParseRule
proc parsePrecedence(precedence: Precedence)

proc binary(canAssign: bool) =
  let
    operatorType = parser.previous.`type`
    rule = getRule(operatorType)

  parsePrecedence(Precedence(ord(rule.precedence) + 1))

  case operatorType
  of TOKEN_BANG_EQUAL:
    emitBytes(OP_EQUAL, OP_NOT)
  of TOKEN_EQUAL_EQUAL:
    emitByte(OP_EQUAL)
  of TOKEN_GREATER:
    emitByte(OP_GREATER)
  of TOKEN_GREATER_EQUAL:
    emitBytes(OP_LESS, OP_NOT)
  of TOKEN_LESS:
    emitByte(OP_LESS)
  of TOKEN_LESS_EQUAL:
    emitBytes(OP_GREATER, OP_NOT)
  of TOKEN_PLUS:
    emitByte(OP_ADD)
  of TOKEN_MINUS:
    emitByte(OP_SUBTRACT)
  of TOKEN_STAR:
    emitByte(OP_MULTIPLY)
  of TOKEN_SLASH:
    emitByte(OP_DIVIDE)
  else:
    discard

proc literal(canAssign: bool) =
  case parser.previous.`type`
  of TOKEN_FALSE:
    emitByte(OP_FALSE)
  of TOKEN_NIL:
    emitByte(OP_NIL)
  of TOKEN_TRUE:
    emitByte(OP_TRUE)
  else:
    discard

proc grouping(canAssign: bool) =
  expression()

  consume(TOKEN_RIGHT_PAREN, "Expect ')' after expression.")

proc number(canAssign: bool) =
  var value: float

  discard parseFloat(lexeme(parser.previous), value)

  emitConstant(numberVal(value))

proc string(canAssign: bool) =
  emitConstant(objVal(cast[ptr Obj](copyString(parser.previous.start + 1, parser.previous.length - 2))))

proc identifierConstant(name: Token): uint8
proc resolveLocal(compiler: ptr Compiler, name: Token): int32

proc namedVariable(name: Token, canAssign: bool) =
  var
    getOp: OpCode
    setOp: OpCode
    arg = resolveLocal(current, name)

  if arg != -1:
    getOp = OP_GET_LOCAL
    setOp = OP_SET_LOCAL
  else:
    arg = identifierConstant(name).int32
    getOp = OP_GET_GLOBAL
    setOp = OP_SET_GLOBAL

  if canAssign and match(TOKEN_EQUAL):
    expression()

    emitBytes(setOp, uint8(arg))
  else:
    emitBytes(getOp, uint8(arg))

proc variable(canAssign: bool) =
  namedVariable(parser.previous, canAssign)

proc unary(canAssign: bool) =
  let operatorType = parser.previous.`type`

  parsePrecedence(PREC_UNARY)

  case operatorType
  of TOKEN_BANG:
    emitByte(OP_NOT)
  of TOKEN_MINUS:
    emitByte(OP_NEGATE)
  else:
    discard

let rules: array[40, ParseRule] = [
  ParseRule(prefix: grouping, infix: nil, precedence: PREC_NONE), # TOKEN_LEFT_PAREN
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_RIGHT_PAREN
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_LEFT_BRACE
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_RIGHT_BRACE
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_COMMA
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_DOT
  ParseRule(prefix: unary, infix: binary, precedence: PREC_TERM), # TOKEN_MINUS
  ParseRule(prefix: nil, infix: binary, precedence: PREC_TERM),   # TOKEN_PLUS
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_SEMICOLON
  ParseRule(prefix: nil, infix: binary, precedence: PREC_FACTOR), # TOKEN_SLASH
  ParseRule(prefix: nil, infix: binary, precedence: PREC_FACTOR), # TOKEN_STAR
  ParseRule(prefix: unary, infix: nil, precedence: PREC_NONE),    # TOKEN_BANG
  ParseRule(prefix: nil, infix: binary, precedence: PREC_EQUALITY), # TOKEN_BANG_EQUAL
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_EQUAL
  ParseRule(prefix: nil, infix: binary, precedence: PREC_EQUALITY), # TOKEN_EQUAL_EQUAL
  ParseRule(prefix: nil, infix: binary, precedence: PREC_COMPARISON), # TOKEN_GREATER
  ParseRule(prefix: nil, infix: binary, precedence: PREC_COMPARISON), # TOKEN_GREATER_EQUAL
  ParseRule(prefix: nil, infix: binary, precedence: PREC_COMPARISON), # TOKEN_LESS
  ParseRule(prefix: nil, infix: binary, precedence: PREC_COMPARISON), # TOKEN_LESS_EQUAL
  ParseRule(prefix: variable, infix: nil, precedence: PREC_NONE),      # TOKEN_IDENTIFIER
  ParseRule(prefix: string, infix: nil, precedence: PREC_NONE),      # TOKEN_STRING
  ParseRule(prefix: number, infix: nil, precedence: PREC_NONE),   # TOKEN_NUMBER
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_AND
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_CLASS
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_ELSE
  ParseRule(prefix: literal, infix: nil, precedence: PREC_NONE),  # TOKEN_FALSE
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_FOR
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_FUN
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_IF
  ParseRule(prefix: literal, infix: nil, precedence: PREC_NONE),  # TOKEN_NIL
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_OR
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_PRINT
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_RETURN
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_SUPER
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_THIS
  ParseRule(prefix: literal, infix: nil, precedence: PREC_NONE),  # TOKEN_TRUE
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_VAR
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_WHILE
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_ERROR
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE)       # TOKEN_EOF
]

proc parsePrecedence(precedence: Precedence) =
  advance()

  let prefixRule = getRule(parser.previous.`type`).prefix

  if isNil(prefixRule):
    error("Expect expression.")
    return

  let canAssign = precedence <= PREC_ASSIGNMENT

  prefixRule(canAssign)

  while precedence <= getRule(parser.current.`type`).precedence:
    advance()

    let infixRule = getRule(parser.previous.`type`).infix

    infixRule(canAssign)

  if canAssign and match(TOKEN_EQUAL):
    error("Invalid assignment target.")

proc identifierConstant(name: Token): uint8 =
  makeConstant(objVal(cast[ptr Obj](copyString(name.start, name.length))))

proc identifiersEqual(a: Token, b: Token): bool =
  if a.length != b.length:
    return false

  cmpMem(a.start, b.start, a.length) == 0

proc resolveLocal(compiler: ptr Compiler, name: Token): int32 =
  for i in countdown(compiler.localCount - 1, 0):
    let local = cast[ptr Local](addr compiler.locals[i])

    if identifiersEqual(name, local.name):
      if local.depth == -1:
        error("Can't read local variable in its own initializer.")

      return i

  -1

proc addLocal(name: Token) =
  if current.localCount == UINT8_COUNT:
    error("Too many local variables in function.")
    return

  let tmp = current.localCount

  inc(current.localCount)

  var local = cast[ptr Local](addr current.locals[tmp])

  local.name = name
  local.depth = -1

proc declareVariable() =
  if current.scopeDepth == 0:
    return

  let name = parser.previous

  for i in countdown(current.localCount  - 1, 0):
    let local = cast[ptr Local](addr current.locals[i])

    if (local.depth != -1) and (local.depth < current.scopeDepth):
      break

    if identifiersEqual(name, local.name):
      error("Already a variable with this name in this scope.")

  addLocal(name)

proc parseVariable(errorMessage: string): uint8 =
  consume(TOKEN_IDENTIFIER, errorMessage)

  declareVariable()

  if current.scopeDepth > 0:
    return 0

  identifierConstant(parser.previous)

proc markInitialized() =
  current.locals[current.localCount - 1].depth = current.scopeDepth

proc defineVariable(global: uint8) =
  if current.scopeDepth > 0:
    markInitialized()
    return

  emitBytes(OP_DEFINE_GLOBAL, global)

proc getRule(`type`: TokenType): ptr ParseRule =
  addr rules[ord(`type`)]

proc expression() =
  parsePrecedence(PREC_ASSIGNMENT)

proc `block`() =
  while not(check(TOKEN_RIGHT_BRACE)) and not(check(TOKEN_EOF)):
    declaration()

  consume(TOKEN_RIGHT_BRACE, "Expect '}' after block.")

proc varDeclaration() =
  let global = parseVariable("Expect variable name.")

  if match(TOKEN_EQUAL):
    expression()
  else:
    emitByte(OP_NIL)

  consume(TOKEN_SEMICOLON, "Expect ';' after variable declaration.")

  defineVariable(global)

proc expressionStatement() =
  expression()

  consume(TOKEN_SEMICOLON, "Expect ';' after expression.")

  emitByte(OP_POP)

proc printStatement() =
  expression()

  consume(TOKEN_SEMICOLON, "Expect ';' after value.")

  emitByte(OP_PRINT)

proc synchronize() =
  parser.panicMode = false

  while parser.current.`type` != TOKEN_EOF:
    if parser.previous.`type` == TOKEN_SEMICOLON:
      return

    case parser.current.`type`:
    of TOKEN_CLASS, TOKEN_FUN, TOKEN_VAR, TOKEN_FOR, TOKEN_IF, TOKEN_WHILE, TOKEN_PRINT, TOKEN_RETURN:
      return
    else:
      discard

    advance()

proc declaration() =
  if match(TOKEN_VAR):
    varDeclaration()
  else:
    statement()

  if parser.panicMode:
    synchronize()

proc statement() =
  if match(TOKEN_PRINT):
    printStatement()
  elif match(TOKEN_LEFT_BRACE):
    beginScope()

    `block`()

    endScope()
  else:
    expressionStatement()

proc compile*(source: var string, chunk: var Chunk): bool =
  initScanner(source)

  var compiler: Compiler

  initCompiler(compiler)

  compilingChunk = addr chunk

  advance()

  while not match(TOKEN_EOF):
    declaration()

  endCompiler()

  not parser.hadError
