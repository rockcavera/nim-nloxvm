import std/[parseutils, strformat]

import ./chunk, ./common, ./globals, ./object, ./scanner, ./types, ./value_helpers

when defined(DEBUG_PRINT_CODE):
  import ./debug

import ./private/pointer_arithmetics

const UINT16_MAX = high(uint16).int32

var
  parser: Parser
  currentClass: ptr ClassCompiler = nil

template lexeme(token: Token): openArray[char] =
  toOpenArray(cast[cstring](token.start), 0, token.length - 1)

proc currentChunk(): var Chunk =
  current.function.chunk

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

proc errorAtCurrent(message: string) =
  errorAt(parser.current, cast[ptr char](addr message[0]))

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

proc emitLoop(loopStart: int32) =
  emitByte(OP_LOOP)

  let offset = currentChunk().count - loopStart + 2

  if offset > UINT16_MAX:
    error("Loop body too large.")

  emitByte(uint8((offset shr 8) and 0xff))
  emitByte(uint8(offset and 0xff))

proc emitJump(instruction: uint8): int32 =
  emitByte(instruction)
  emitByte(0xff)
  emitByte(0xff)

  currentChunk().count - 2

template emitJump(instruction: OpCode): int32 =
  emitJump(uint8(instruction))

proc emitReturn() =
  if current.`type` == TYPE_INITIALIZER:
    emitBytes(OP_GET_LOCAL, 0)
  else:
    emitByte(OP_NIL)

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

proc patchJump(offset: int32) =
  let jump = currentChunk().count - offset - 2

  if jump > UINT16_MAX:
    error("Too much code to jump over.")

  currentChunk().code[offset] = uint8((jump shr 8) and 0xff)
  currentChunk().code[offset + 1] = uint8(jump and 0xff)

proc initCompiler(compiler: var Compiler, `type`: FunctionType) =
  compiler.enclosing = current
  compiler.function = nil
  compiler.`type` = `type`
  compiler.localCount = 0
  compiler.scopeDepth = 0
  compiler.function = newFunction()
  current = addr compiler

  if `type` != TYPE_SCRIPT:
    current.function.name = copyString(parser.previous.start, parser.previous.length)

  var local = cast[ptr Local](addr current.locals[current.localCount])

  inc(current.localCount)

  local.depth = 0
  local.isCaptured = false

  if `type` != TYPE_FUNCTION:
    local.name.start = cast[ptr char](cstring"this")
    local.name.length = 4
  else:
    local.name.start = cast[ptr char](cstring"")
    local.name.length = 0

proc endCompiler(): ptr ObjFunction =
  emitReturn()

  result = current.function

  when defined(DEBUG_PRINT_CODE):
    if not parser.hadError:
      disassembleChunk(currentChunk(),
                       if not isNil(result.name): result.name.chars
                       else: cast[ptr char](cstring"<script>"))

  current = current.enclosing

proc beginScope() =
  inc(current.scopeDepth)

proc endScope() =
  dec(current.scopeDepth)

  while (current.localCount > 0) and (current.locals[current.localCount - 1].depth > current.scopeDepth):
    if current.locals[current.localCount - 1].isCaptured:
      emitByte(OP_CLOSE_UPVALUE)
    else:
      emitByte(OP_POP)

    dec(current.localCount)

proc expression()
proc statement()
proc declaration()
proc getRule(`type`: TokenType): ptr ParseRule
proc parsePrecedence(precedence: Precedence)

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

proc addUpvalue(compiler: ptr Compiler, index: uint8, isLocal: bool): int32 =
  let upvalueCount = compiler.function.upvalueCount

  for i in 0'i32 ..< upvalueCount:
    let upvalue = compiler.upvalues[i]

    if upvalue.index == index and upvalue.isLocal == isLocal:
      return i

  if upvalueCount == UINT8_COUNT:
    error("Too many closure variables in function.")
    return 0

  compiler.upvalues[upvalueCount].isLocal = isLocal
  compiler.upvalues[upvalueCount].index = index

  inc(compiler.function.upvalueCount)

  return upvalueCount

proc resolveUpvalue(compiler: ptr Compiler, name: Token): int32 =
  if isNil(compiler.enclosing):
    return -1

  let local = resolveLocal(compiler.enclosing, name)

  if local != -1:
    compiler.enclosing.locals[local].isCaptured = true
    return addUpvalue(compiler, uint8(local), true)

  let upvalue = resolveUpvalue(compiler.enclosing, name)

  if upvalue != -1:
    return addUpvalue(compiler, uint8(upvalue), false)

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
  local.isCaptured = false

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
  if current.scopeDepth == 0:
    return

  current.locals[current.localCount - 1].depth = current.scopeDepth

proc defineVariable(global: uint8) =
  if current.scopeDepth > 0:
    markInitialized()
    return

  emitBytes(OP_DEFINE_GLOBAL, global)

proc argumentList(): uint8 =
  if not check(TOKEN_RIGHT_PAREN):
    while true:
      expression()

      if result == 255:
        error("Can't have more than 255 arguments.")

      inc(result)

      if not match(TOKEN_COMMA):
        break

  consume(TOKEN_RIGHT_PAREN, "Expect ')' after arguments.")

proc `and`(canAssign: bool) =
  let endJump = emitJump(OP_JUMP_IF_FALSE)

  emitByte(OP_POP)

  parsePrecedence(PREC_AND)

  patchJump(endJump)

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

proc call(canAssign: bool) =
  let argCount = argumentList()

  emitBytes(OP_CALL, argCount)

proc dot(canAssign: bool) =
  consume(TOKEN_IDENTIFIER, "Expect property name after '.'.")

  let name = identifierConstant(parser.previous)

  if canAssign and match(TOKEN_EQUAL):
    expression()

    emitBytes(OP_SET_PROPERTY, name)
  elif match(TOKEN_LEFT_PAREN):
    let argCount = argumentList()

    emitBytes(OP_INVOKE, name)

    emitByte(argCount)
  else:
    emitBytes(OP_GET_PROPERTY, name)

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

proc `or`(canAssign: bool) =
  let
    elseJump = emitJump(OP_JUMP_IF_FALSE)
    endJump = emitJump(OP_JUMP)

  patchJump(elseJump)

  emitByte(OP_POP)

  parsePrecedence(PREC_OR)

  patchJump(endJump)

proc string(canAssign: bool) =
  emitConstant(objVal(cast[ptr Obj](copyString(parser.previous.start + 1, parser.previous.length - 2))))

proc namedVariable(name: Token, canAssign: bool) =
  var
    getOp: OpCode
    setOp: OpCode
    arg = resolveLocal(current, name)

  if arg != -1:
    getOp = OP_GET_LOCAL
    setOp = OP_SET_LOCAL
  else:
    arg = resolveUpvalue(current, name)

    if arg != -1:
      getOp = OP_GET_UPVALUE
      setOp = OP_SET_UPVALUE
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

proc this(canAssign: bool) =
  if isNil(currentClass):
    error("Can't use 'this' outside of a class.")
    return

  variable(false)

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
  ParseRule(prefix: grouping, infix: call, precedence: PREC_CALL), # TOKEN_LEFT_PAREN
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_RIGHT_PAREN
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_LEFT_BRACE
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_RIGHT_BRACE
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_COMMA
  ParseRule(prefix: nil, infix: dot, precedence: PREC_CALL),      # TOKEN_DOT
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
  ParseRule(prefix: nil, infix: `and`, precedence: PREC_AND),      # TOKEN_AND
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_CLASS
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_ELSE
  ParseRule(prefix: literal, infix: nil, precedence: PREC_NONE),  # TOKEN_FALSE
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_FOR
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_FUN
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_IF
  ParseRule(prefix: literal, infix: nil, precedence: PREC_NONE),  # TOKEN_NIL
  ParseRule(prefix: nil, infix: `or`, precedence: PREC_OR),      # TOKEN_OR
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_PRINT
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_RETURN
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_SUPER
  ParseRule(prefix: this, infix: nil, precedence: PREC_NONE),      # TOKEN_THIS
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

proc getRule(`type`: TokenType): ptr ParseRule =
  addr rules[ord(`type`)]

proc expression() =
  parsePrecedence(PREC_ASSIGNMENT)

proc `block`() =
  while not(check(TOKEN_RIGHT_BRACE)) and not(check(TOKEN_EOF)):
    declaration()

  consume(TOKEN_RIGHT_BRACE, "Expect '}' after block.")

proc function(`type`: FunctionType) =
  var compiler: Compiler

  initCompiler(compiler, `type`)

  beginScope()

  consume(TOKEN_LEFT_PAREN, "Expect '(' after function name.")

  if not check(TOKEN_RIGHT_PAREN):
    while true:
      inc(current.function.arity)

      if current.function.arity > 255:
        errorAtCurrent("Can't have more than 255 parameters.")

      let constant = parseVariable("Expect parameter name.")

      defineVariable(constant)

      if not match(TOKEN_COMMA):
        break

  consume(TOKEN_RIGHT_PAREN, "Expect ')' after parameters.")
  consume(TOKEN_LEFT_BRACE, "Expect '{' before function body.")

  `block`()

  let function = endCompiler()

  emitBytes(OP_CLOSURE, makeConstant(objVal(cast[ptr Obj](function))))

  for i in 0 ..< function.upvalueCount:
    emitByte(if compiler.upvalues[i].isLocal: 1 else: 0)
    emitByte(compiler.upvalues[i].index)

proc `method`() =
  consume(TOKEN_IDENTIFIER, "Expect method name.")

  let constant = identifierConstant(parser.previous)

  var `type` = TYPE_METHOD

  if parser.previous.length == 4 and cmpMem(parser.previous.start, cstring"init", 4) == 0:
    `type` = TYPE_INITIALIZER

  function(`type`)

  emitBytes(OP_METHOD, constant)

proc classDeclaration() =
  consume(TOKEN_IDENTIFIER, "Expect class name.")

  let
    className = parser.previous
    nameConstant = identifierConstant(parser.previous)

  declareVariable()

  emitBytes(OP_CLASS, nameConstant)

  defineVariable(nameConstant)

  var classCompiler: ClassCompiler

  classCompiler.enclosing = currentClass
  currentClass = addr classCompiler

  namedVariable(className, false)

  consume(TOKEN_LEFT_BRACE, "Expect '{' before class body.")

  while not(check(TOKEN_RIGHT_BRACE)) and not(check(TOKEN_EOF)):
    `method`()

  consume(TOKEN_RIGHT_BRACE, "Expect '}' after class body.")

  emitByte(OP_POP)

  currentClass = currentClass.enclosing

proc funDeclaration() =
  let global = parseVariable("Expect function name.")

  markInitialized()

  function(TYPE_FUNCTION)

  defineVariable(global)

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

proc forStatement() =
  beginScope()

  consume(TOKEN_LEFT_PAREN, "Expect '(' after 'for'.")

  if match(TOKEN_SEMICOLON):
    discard
  elif match(TOKEN_VAR):
    varDeclaration()
  else:
    expressionStatement()

  var loopStart = currentChunk().count

  var exitJump = -1'i32

  if not match(TOKEN_SEMICOLON):
    expression()

    consume(TOKEN_SEMICOLON, "Expect ';' after loop condition.")

    exitJump = emitJump(OP_JUMP_IF_FALSE)

    emitByte(OP_POP)

  if not match(TOKEN_RIGHT_PAREN):
    let
      bodyJump = emitJump(OP_JUMP)
      incrementStart = currentChunk().count

    expression()

    emitByte(OP_POP)

    consume(TOKEN_RIGHT_PAREN, "Expect ')' after for clauses.")

    emitLoop(loopStart)

    loopStart = incrementStart

    patchJump(bodyJump)

  statement()

  emitLoop(loopStart)

  if exitJump != -1:
    patchJump(exitJump)

    emitByte(OP_POP)

  endScope()

proc ifStatement() =
  consume(TOKEN_LEFT_PAREN, "Expect '(' after 'if'.")

  expression()

  consume(TOKEN_RIGHT_PAREN, "Expect ')' after condition.")

  let thenJump = emitJump(OP_JUMP_IF_FALSE)

  emitByte(OP_POP)

  statement()

  let elseJump = emitJump(OP_JUMP)

  patchJump(thenJump)

  emitByte(OP_POP)

  if match(TOKEN_ELSE):
    statement()

  patchJump(elseJump)

proc printStatement() =
  expression()

  consume(TOKEN_SEMICOLON, "Expect ';' after value.")

  emitByte(OP_PRINT)

proc returnStatement() =
  if current.`type` == TYPE_SCRIPT:
    error("Can't return from top-level code.")

  if match(TOKEN_SEMICOLON):
    emitReturn()
  else:
    if current.`type` == TYPE_INITIALIZER:
      error("Can't return a value from an initializer.")

    expression()

    consume(TOKEN_SEMICOLON, "Expect ';' after return value.")

    emitByte(OP_RETURN)

proc whileStatement() =
  let loopStart = currentChunk().count

  consume(TOKEN_LEFT_PAREN, "Expect '(' after 'while'.")

  expression()

  consume(TOKEN_RIGHT_PAREN, "Expect ')' after condition.")

  let exitJump = emitJump(OP_JUMP_IF_FALSE)

  emitByte(OP_POP)

  statement()

  emitLoop(loopStart)

  patchJump(exitJump)

  emitByte(OP_POP)

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
  if match(TOKEN_CLASS):
    classDeclaration()
  elif match(TOKEN_FUN):
    funDeclaration()
  elif match(TOKEN_VAR):
    varDeclaration()
  else:
    statement()

  if parser.panicMode:
    synchronize()

proc statement() =
  if match(TOKEN_PRINT):
    printStatement()
  elif match(TOKEN_FOR):
    forStatement()
  elif match(TOKEN_IF):
    ifStatement()
  elif match(TOKEN_RETURN):
    returnStatement()
  elif match(TOKEN_WHILE):
    whileStatement()
  elif match(TOKEN_LEFT_BRACE):
    beginScope()

    `block`()

    endScope()
  else:
    expressionStatement()

proc compile*(source: var string): ptr ObjFunction =
  initScanner(source)

  var compiler: Compiler

  initCompiler(compiler, TYPE_SCRIPT)

  parser.hadError = false
  parser.panicMode = false

  advance()

  while not match(TOKEN_EOF):
    declaration()

  let function = endCompiler()

  return if parser.hadError: nil else: function
