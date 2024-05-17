import std/parseutils

import ./chunk, ./common, ./globals, ./object, ./scanner, ./types, ./value_helpers

when defined(debugPrintCode):
  import ./debug

import ./private/pointer_arithmetics

const uint16Max = high(uint16).int32

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

  write(stderr, "[line ", $token.line, "] Error")

  if token.`type` == TokenEof:
    write(stderr, " at end")
  elif token.`type` == TokenError:
    discard
  else:
    write(stderr, " at '")

    discard writeBuffer(stderr, token.start, token.length)

    write(stderr, '\'')

  write(stderr, ": ")
  write(stderr, cast[cstring](message))
  write(stderr, '\n')

  parser.hadError = true

proc error(message: ptr char) =
  errorAt(parser.previous, message)

proc error(message: string) =
  errorAt(parser.previous, addr message[0])

proc errorAtCurrent(message: ptr char) =
  errorAt(parser.current, message)

proc errorAtCurrent(message: string) =
  errorAt(parser.current, addr message[0])

proc advance() =
  parser.previous = parser.current

  while true:
    parser.current = scanToken()

    if parser.current.`type` != TokenError:
      break

    errorAtCurrent(parser.current.start)

proc consume(`type`: TokenType, message: string) =
  if parser.current.`type` == `type`:
    advance()
    return

  errorAtCurrent(addr message[0])

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
  emitByte(OpLoop)

  let offset = currentChunk().count - loopStart + 2

  if offset > uint16Max:
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
  if current.`type` == TypeInitializer:
    emitBytes(OpGetLocal, 0)
  else:
    emitByte(OpNil)

  emitByte(OpReturn)

proc makeConstant(value: Value): uint8 =
  const uint8Max = high(uint8).int32

  let constant = addConstant(currentChunk(), value)

  if constant > uint8Max:
    error("Too many constants in one chunk.")
    return 0'u8

  uint8(constant)

proc emitConstant(value: Value) =
  emitBytes(OpConstant, makeConstant(value))

proc patchJump(offset: int32) =
  let jump = currentChunk().count - offset - 2

  if jump > uint16Max:
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

  if `type` != TypeScript:
    current.function.name = copyString(parser.previous.start, parser.previous.length)

  var local = addr current.locals[current.localCount]

  inc(current.localCount)

  local.depth = 0
  local.isCaptured = false

  if `type` != TypeFunction:
    local.name.start = cast[ptr char](cstring"this")
    local.name.length = 4
  else:
    local.name.start = cast[ptr char](cstring"")
    local.name.length = 0

proc endCompiler(): ptr ObjFunction =
  emitReturn()

  result = current.function

  when defined(debugPrintCode):
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
      emitByte(OpCloseUpvalue)
    else:
      emitByte(OpPop)

    dec(current.localCount)

proc expression()
proc statement()
proc declaration()
proc getRule(`type`: TokenType): ptr ParseRule
proc parsePrecedence(precedence: Precedence)

proc identifierConstant(name: Token): uint8 =
  makeConstant(objVal(copyString(name.start, name.length)))

proc identifiersEqual(a: Token, b: Token): bool =
  if a.length != b.length:
    return false

  cmpMem(a.start, b.start, a.length) == 0

proc resolveLocal(compiler: ptr Compiler, name: Token): int32 =
  for i in countdown(compiler.localCount - 1, 0):
    let local = addr compiler.locals[i]

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

  if upvalueCount == uint8Count:
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
  if current.localCount == uint8Count:
    error("Too many local variables in function.")
    return

  let tmp = current.localCount

  inc(current.localCount)

  var local = addr current.locals[tmp]

  local.name = name
  local.depth = -1
  local.isCaptured = false

proc declareVariable() =
  if current.scopeDepth == 0:
    return

  let name = parser.previous

  for i in countdown(current.localCount  - 1, 0):
    let local = addr current.locals[i]

    if (local.depth != -1) and (local.depth < current.scopeDepth):
      break

    if identifiersEqual(name, local.name):
      error("Already a variable with this name in this scope.")

  addLocal(name)

proc parseVariable(errorMessage: string): uint8 =
  consume(TokenIdentifier, errorMessage)

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

  emitBytes(OpDefineGlobal, global)

proc argumentList(): uint8 =
  if not check(TokenRightParen):
    while true:
      expression()

      if result == 255:
        error("Can't have more than 255 arguments.")

      inc(result)

      if not match(TokenComma):
        break

  consume(TokenRightParen, "Expect ')' after arguments.")

proc `and`(canAssign: bool) =
  let endJump = emitJump(OpJumpIfFalse)

  emitByte(OpPop)

  parsePrecedence(PrecAnd)

  patchJump(endJump)

proc binary(canAssign: bool) =
  let
    operatorType = parser.previous.`type`
    rule = getRule(operatorType)

  parsePrecedence(Precedence(ord(rule.precedence) + 1))

  case operatorType
  of TokenBangEqual:
    emitBytes(OpEqual, OpNot)
  of TokenEqualEqual:
    emitByte(OpEqual)
  of TokenGreater:
    emitByte(OpGreater)
  of TokenGreaterEqual:
    emitBytes(OpLess, OpNot)
  of TokenLess:
    emitByte(OpLess)
  of TokenLessEqual:
    emitBytes(OpGreater, OpNot)
  of TokenPlus:
    emitByte(OpAdd)
  of TokenMinus:
    emitByte(OpSubtract)
  of TokenStar:
    emitByte(OpMultiply)
  of TokenSlash:
    emitByte(OpDivide)
  else:
    discard

proc call(canAssign: bool) =
  let argCount = argumentList()

  emitBytes(OpCall, argCount)

proc dot(canAssign: bool) =
  consume(TokenIdentifier, "Expect property name after '.'.")

  let name = identifierConstant(parser.previous)

  if canAssign and match(TokenEqual):
    expression()

    emitBytes(OpSetProperty, name)
  elif match(TokenLeftParen):
    let argCount = argumentList()

    emitBytes(OpInvoke, name)

    emitByte(argCount)
  else:
    emitBytes(OpGetProperty, name)

proc literal(canAssign: bool) =
  case parser.previous.`type`
  of TokenFalse:
    emitByte(OpFalse)
  of TokenNil:
    emitByte(OpNil)
  of TokenTrue:
    emitByte(OpTrue)
  else:
    discard

proc grouping(canAssign: bool) =
  expression()

  consume(TokenRightParen, "Expect ')' after expression.")

proc number(canAssign: bool) =
  var value: float

  discard parseFloat(lexeme(parser.previous), value)

  emitConstant(numberVal(value))

proc `or`(canAssign: bool) =
  let
    elseJump = emitJump(OpJumpIfFalse)
    endJump = emitJump(OpJump)

  patchJump(elseJump)

  emitByte(OpPop)

  parsePrecedence(PrecOr)

  patchJump(endJump)

proc string(canAssign: bool) =
  emitConstant(objVal(copyString(parser.previous.start + 1, parser.previous.length - 2)))

proc namedVariable(name: Token, canAssign: bool) =
  var
    getOp: OpCode
    setOp: OpCode
    arg = resolveLocal(current, name)

  if arg != -1:
    getOp = OpGetLocal
    setOp = OpSetLocal
  else:
    arg = resolveUpvalue(current, name)

    if arg != -1:
      getOp = OpGetUpvalue
      setOp = OpSetUpvalue
    else:
      arg = identifierConstant(name).int32
      getOp = OpGetGlobal
      setOp = OpSetGlobal

  if canAssign and match(TokenEqual):
    expression()

    emitBytes(setOp, uint8(arg))
  else:
    emitBytes(getOp, uint8(arg))

proc variable(canAssign: bool) =
  namedVariable(parser.previous, canAssign)

proc syntheticToken(text: cstring): Token =
  result.start = cast[ptr char](text)
  result.length = len(text).int32

proc super(canAssign: bool) =
  if isNil(currentClass):
    error("Can't use 'super' outside of a class.")
  elif not currentClass.hasSuperclass:
    error("Can't use 'super' in a class with no superclass.")

  consume(TokenDot, "Expect '.' after 'super'.")
  consume(TokenIdentifier, "Expect superclass method name.")

  let name = identifierConstant(parser.previous)

  namedVariable(syntheticToken(cstring"this"), false)

  if match(TokenLeftParen):
    let argCount = argumentList()

    namedVariable(syntheticToken(cstring"super"), false)

    emitBytes(OpSuperInvoke, name)
    emitByte(argCount)
  else:
    namedVariable(syntheticToken(cstring"super"), false)
    emitBytes(OpGetSuper, name)

proc this(canAssign: bool) =
  if isNil(currentClass):
    error("Can't use 'this' outside of a class.")
    return

  variable(false)

proc unary(canAssign: bool) =
  let operatorType = parser.previous.`type`

  parsePrecedence(PrecUnary)

  case operatorType
  of TokenBang:
    emitByte(OpNot)
  of TokenMinus:
    emitByte(OpNegate)
  else:
    discard

let rules: array[40, ParseRule] = [
  ParseRule(prefix: grouping, infix: call, precedence: PrecCall),    # TokenLeftParen
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenRightParen
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenLeftBrace
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenRightBrace
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenComma
  ParseRule(prefix: nil, infix: dot, precedence: PrecCall),          # TokenDot
  ParseRule(prefix: unary, infix: binary, precedence: PrecTerm),     # TokenMinus
  ParseRule(prefix: nil, infix: binary, precedence: PrecTerm),       # TokenPlus
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenSemicolon
  ParseRule(prefix: nil, infix: binary, precedence: PrecFactor),     # TokenSlash
  ParseRule(prefix: nil, infix: binary, precedence: PrecFactor),     # TokenStar
  ParseRule(prefix: unary, infix: nil, precedence: PrecNone),        # TokenBang
  ParseRule(prefix: nil, infix: binary, precedence: PrecEquality),   # TokenBangEqual
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenEqual
  ParseRule(prefix: nil, infix: binary, precedence: PrecEquality),   # TokenEqualEqual
  ParseRule(prefix: nil, infix: binary, precedence: PrecComparison), # TokenGreater
  ParseRule(prefix: nil, infix: binary, precedence: PrecComparison), # TokenGreaterEqual
  ParseRule(prefix: nil, infix: binary, precedence: PrecComparison), # TokenLess
  ParseRule(prefix: nil, infix: binary, precedence: PrecComparison), # TokenLessEqual
  ParseRule(prefix: variable, infix: nil, precedence: PrecNone),     # TokenIdentifier
  ParseRule(prefix: string, infix: nil, precedence: PrecNone),       # TokenString
  ParseRule(prefix: number, infix: nil, precedence: PrecNone),       # TokenNumber
  ParseRule(prefix: nil, infix: `and`, precedence: PrecAnd),         # TokenAnd
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenClass
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenElse
  ParseRule(prefix: literal, infix: nil, precedence: PrecNone),      # TokenFalse
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenFor
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenFun
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenIf
  ParseRule(prefix: literal, infix: nil, precedence: PrecNone),      # TokenNil
  ParseRule(prefix: nil, infix: `or`, precedence: PrecOr),           # TokenOr
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenPrint
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenReturn
  ParseRule(prefix: super, infix: nil, precedence: PrecNone),        # TokenSuper
  ParseRule(prefix: this, infix: nil, precedence: PrecNone),         # TokenThis
  ParseRule(prefix: literal, infix: nil, precedence: PrecNone),      # TokenTrue
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenVar
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenWhile
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone),          # TokenError
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone)           # TokenEof
]

proc parsePrecedence(precedence: Precedence) =
  advance()

  let prefixRule = getRule(parser.previous.`type`).prefix

  if isNil(prefixRule):
    error("Expect expression.")
    return

  let canAssign = precedence <= PrecAssignment

  prefixRule(canAssign)

  while precedence <= getRule(parser.current.`type`).precedence:
    advance()

    let infixRule = getRule(parser.previous.`type`).infix

    infixRule(canAssign)

  if canAssign and match(TokenEqual):
    error("Invalid assignment target.")

proc getRule(`type`: TokenType): ptr ParseRule =
  addr rules[ord(`type`)]

proc expression() =
  parsePrecedence(PrecAssignment)

proc `block`() =
  while not(check(TokenRightBrace)) and not(check(TokenEof)):
    declaration()

  consume(TokenRightBrace, "Expect '}' after block.")

proc function(`type`: FunctionType) =
  var compiler: Compiler

  initCompiler(compiler, `type`)

  beginScope()

  consume(TokenLeftParen, "Expect '(' after function name.")

  if not check(TokenRightParen):
    while true:
      inc(current.function.arity)

      if current.function.arity > 255:
        errorAtCurrent("Can't have more than 255 parameters.")

      let constant = parseVariable("Expect parameter name.")

      defineVariable(constant)

      if not match(TokenComma):
        break

  consume(TokenRightParen, "Expect ')' after parameters.")
  consume(TokenLeftBrace, "Expect '{' before function body.")

  `block`()

  let function = endCompiler()

  emitBytes(OpClosure, makeConstant(objVal(function)))

  for i in 0 ..< function.upvalueCount:
    emitByte(if compiler.upvalues[i].isLocal: 1 else: 0)
    emitByte(compiler.upvalues[i].index)

proc `method`() =
  consume(TokenIdentifier, "Expect method name.")

  let constant = identifierConstant(parser.previous)

  var `type` = TypeMethod

  if parser.previous.length == 4 and cmpMem(parser.previous.start, cstring"init", 4) == 0:
    `type` = TypeInitializer

  function(`type`)

  emitBytes(OpMethod, constant)

proc classDeclaration() =
  consume(TokenIdentifier, "Expect class name.")

  let
    className = parser.previous
    nameConstant = identifierConstant(parser.previous)

  declareVariable()

  emitBytes(OpClass, nameConstant)

  defineVariable(nameConstant)

  var classCompiler: ClassCompiler

  classCompiler.hasSuperclass = false
  classCompiler.enclosing = currentClass
  currentClass = addr classCompiler

  if match(TokenLess):
    consume(TokenIdentifier, "Expect superclass name.")

    variable(false)

    if identifiersEqual(className, parser.previous):
      error("A class can't inherit from itself.")

    beginScope()

    addLocal(syntheticToken(cstring"super"))

    defineVariable(0)

    namedVariable(className, false)

    emitByte(OpInherit)

    classCompiler.hasSuperclass = true

  namedVariable(className, false)

  consume(TokenLeftBrace, "Expect '{' before class body.")

  while not(check(TokenRightBrace)) and not(check(TokenEof)):
    `method`()

  consume(TokenRightBrace, "Expect '}' after class body.")

  emitByte(OpPop)

  if classCompiler.hasSuperclass:
    endScope()

  currentClass = currentClass.enclosing

proc funDeclaration() =
  let global = parseVariable("Expect function name.")

  markInitialized()

  function(TypeFunction)

  defineVariable(global)

proc varDeclaration() =
  let global = parseVariable("Expect variable name.")

  if match(TokenEqual):
    expression()
  else:
    emitByte(OpNil)

  consume(TokenSemicolon, "Expect ';' after variable declaration.")

  defineVariable(global)

proc expressionStatement() =
  expression()

  consume(TokenSemicolon, "Expect ';' after expression.")

  emitByte(OpPop)

proc forStatement() =
  beginScope()

  consume(TokenLeftParen, "Expect '(' after 'for'.")

  if match(TokenSemicolon):
    discard
  elif match(TokenVar):
    varDeclaration()
  else:
    expressionStatement()

  var loopStart = currentChunk().count

  var exitJump = -1'i32

  if not match(TokenSemicolon):
    expression()

    consume(TokenSemicolon, "Expect ';' after loop condition.")

    exitJump = emitJump(OpJumpIfFalse)

    emitByte(OpPop)

  if not match(TokenRightParen):
    let
      bodyJump = emitJump(OpJump)
      incrementStart = currentChunk().count

    expression()

    emitByte(OpPop)

    consume(TokenRightParen, "Expect ')' after for clauses.")

    emitLoop(loopStart)

    loopStart = incrementStart

    patchJump(bodyJump)

  statement()

  emitLoop(loopStart)

  if exitJump != -1:
    patchJump(exitJump)

    emitByte(OpPop)

  endScope()

proc ifStatement() =
  consume(TokenLeftParen, "Expect '(' after 'if'.")

  expression()

  consume(TokenRightParen, "Expect ')' after condition.")

  let thenJump = emitJump(OpJumpIfFalse)

  emitByte(OpPop)

  statement()

  let elseJump = emitJump(OpJump)

  patchJump(thenJump)

  emitByte(OpPop)

  if match(TokenElse):
    statement()

  patchJump(elseJump)

proc printStatement() =
  expression()

  consume(TokenSemicolon, "Expect ';' after value.")

  emitByte(OpPrint)

proc returnStatement() =
  if current.`type` == TypeScript:
    error("Can't return from top-level code.")

  if match(TokenSemicolon):
    emitReturn()
  else:
    if current.`type` == TypeInitializer:
      error("Can't return a value from an initializer.")

    expression()

    consume(TokenSemicolon, "Expect ';' after return value.")

    emitByte(OpReturn)

proc whileStatement() =
  let loopStart = currentChunk().count

  consume(TokenLeftParen, "Expect '(' after 'while'.")

  expression()

  consume(TokenRightParen, "Expect ')' after condition.")

  let exitJump = emitJump(OpJumpIfFalse)

  emitByte(OpPop)

  statement()

  emitLoop(loopStart)

  patchJump(exitJump)

  emitByte(OpPop)

proc synchronize() =
  parser.panicMode = false

  while parser.current.`type` != TokenEof:
    if parser.previous.`type` == TokenSemicolon:
      return

    case parser.current.`type`:
    of TokenClass, TokenFun, TokenVar, TokenFor, TokenIf, TokenWhile, TokenPrint, TokenReturn:
      return
    else:
      discard

    advance()

proc declaration() =
  if match(TokenClass):
    classDeclaration()
  elif match(TokenFun):
    funDeclaration()
  elif match(TokenVar):
    varDeclaration()
  else:
    statement()

  if parser.panicMode:
    synchronize()

proc statement() =
  if match(TokenPrint):
    printStatement()
  elif match(TokenFor):
    forStatement()
  elif match(TokenIf):
    ifStatement()
  elif match(TokenReturn):
    returnStatement()
  elif match(TokenWhile):
    whileStatement()
  elif match(TokenLeftBrace):
    beginScope()

    `block`()

    endScope()
  else:
    expressionStatement()

proc compile*(source: var string): ptr ObjFunction =
  initScanner(source)

  var compiler: Compiler

  initCompiler(compiler, TypeScript)

  parser.hadError = false
  parser.panicMode = false

  advance()

  while not match(TokenEof):
    declaration()

  let function = endCompiler()

  return if parser.hadError: nil else: function
