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

proc emitByte(vm: var VM, `byte`: uint8) =
  writeChunk(vm, currentChunk(), `byte`, parser.previous.line)

template emitByte(vm: var VM, opCode: OpCode) =
  emitByte(vm, uint8(opCode))

proc emitBytes(vm: var VM, byte1: uint8, byte2: uint8) =
  emitByte(vm, byte1)
  emitByte(vm, byte2)

template emitBytes(vm: var VM, opCode1: OpCode, opCode2: OpCode) =
  emitBytes(vm, uint8(opCode1), uint8(opCode2))

template emitBytes(vm: var VM, opCode: OpCode, `byte`: uint8) =
  emitBytes(vm, uint8(opCode), `byte`)

proc emitLoop(vm: var VM, loopStart: int32) =
  emitByte(vm, OpLoop)

  let offset = currentChunk().count - loopStart + 2

  if offset > uint16Max:
    error("Loop body too large.")

  emitByte(vm, uint8((offset shr 8) and 0xff))
  emitByte(vm, uint8(offset and 0xff))

proc emitJump(vm: var VM, instruction: uint8): int32 =
  emitByte(vm, instruction)
  emitByte(vm, 0xff)
  emitByte(vm, 0xff)

  currentChunk().count - 2

template emitJump(vm: var VM, instruction: OpCode): int32 =
  emitJump(vm, uint8(instruction))

proc emitReturn(vm: var VM, ) =
  if current.`type` == TypeInitializer:
    emitBytes(vm, OpGetLocal, 0)
  else:
    emitByte(vm, OpNil)

  emitByte(vm, OpReturn)

proc makeConstant(vm: var VM, value: Value): uint8 =
  const uint8Max = high(uint8).int32

  let constant = addConstant(vm, currentChunk(), value)

  if constant > uint8Max:
    error("Too many constants in one chunk.")
    return 0'u8

  uint8(constant)

proc emitConstant(vm: var VM, value: Value) =
  emitBytes(vm, OpConstant, makeConstant(vm, value))

proc patchJump(offset: int32) =
  let jump = currentChunk().count - offset - 2

  if jump > uint16Max:
    error("Too much code to jump over.")

  currentChunk().code[offset] = uint8((jump shr 8) and 0xff)
  currentChunk().code[offset + 1] = uint8(jump and 0xff)

proc initCompiler(vm: var VM, compiler: var Compiler, `type`: FunctionType) =
  compiler.enclosing = current
  compiler.function = nil
  compiler.`type` = `type`
  compiler.localCount = 0
  compiler.scopeDepth = 0
  compiler.function = newFunction(vm)
  current = addr compiler

  if `type` != TypeScript:
    current.function.name = copyString(vm, parser.previous.start, parser.previous.length)

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

proc endCompiler(vm: var VM): ptr ObjFunction =
  emitReturn(vm)

  result = current.function

  when defined(debugPrintCode):
    if not parser.hadError:
      disassembleChunk(currentChunk(),
                       if not isNil(result.name): result.name.chars
                       else: cast[ptr char](cstring"<script>"))

  current = current.enclosing

proc beginScope() =
  inc(current.scopeDepth)

proc endScope(vm: var VM) =
  dec(current.scopeDepth)

  while (current.localCount > 0) and (current.locals[current.localCount - 1].depth > current.scopeDepth):
    if current.locals[current.localCount - 1].isCaptured:
      emitByte(vm, OpCloseUpvalue)
    else:
      emitByte(vm, OpPop)

    dec(current.localCount)

proc expression(vm: var VM)
proc statement(vm: var VM)
proc declaration(vm: var VM)
proc getRule(`type`: TokenType): ptr ParseRule
proc parsePrecedence(vm: var VM, precedence: Precedence)

proc identifierConstant(vm: var VM, name: Token): uint8 =
  makeConstant(vm, objVal(copyString(vm, name.start, name.length)))

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

proc parseVariable(vm: var VM, errorMessage: string): uint8 =
  consume(TokenIdentifier, errorMessage)

  declareVariable()

  if current.scopeDepth > 0:
    return 0

  identifierConstant(vm, parser.previous)

proc markInitialized() =
  if current.scopeDepth == 0:
    return

  current.locals[current.localCount - 1].depth = current.scopeDepth

proc defineVariable(vm: var VM, global: uint8) =
  if current.scopeDepth > 0:
    markInitialized()
    return

  emitBytes(vm, OpDefineGlobal, global)

proc argumentList(vm: var VM): uint8 =
  if not check(TokenRightParen):
    while true:
      expression(vm)

      if result == 255:
        error("Can't have more than 255 arguments.")

      inc(result)

      if not match(TokenComma):
        break

  consume(TokenRightParen, "Expect ')' after arguments.")

proc `and`(vm: var VM, canAssign: bool) =
  let endJump = emitJump(vm, OpJumpIfFalse)

  emitByte(vm, OpPop)

  parsePrecedence(vm, PrecAnd)

  patchJump(endJump)

proc binary(vm: var VM, canAssign: bool) =
  let
    operatorType = parser.previous.`type`
    rule = getRule(operatorType)

  parsePrecedence(vm, Precedence(ord(rule.precedence) + 1))

  case operatorType
  of TokenBangEqual:
    emitBytes(vm, OpEqual, OpNot)
  of TokenEqualEqual:
    emitByte(vm, OpEqual)
  of TokenGreater:
    emitByte(vm, OpGreater)
  of TokenGreaterEqual:
    emitBytes(vm, OpLess, OpNot)
  of TokenLess:
    emitByte(vm, OpLess)
  of TokenLessEqual:
    emitBytes(vm, OpGreater, OpNot)
  of TokenPlus:
    emitByte(vm, OpAdd)
  of TokenMinus:
    emitByte(vm, OpSubtract)
  of TokenStar:
    emitByte(vm, OpMultiply)
  of TokenSlash:
    emitByte(vm, OpDivide)
  else:
    discard

proc call(vm: var VM, canAssign: bool) =
  let argCount = argumentList(vm)

  emitBytes(vm, OpCall, argCount)

proc dot(vm: var VM, canAssign: bool) =
  consume(TokenIdentifier, "Expect property name after '.'.")

  let name = identifierConstant(vm, parser.previous)

  if canAssign and match(TokenEqual):
    expression(vm)

    emitBytes(vm, OpSetProperty, name)
  elif match(TokenLeftParen):
    let argCount = argumentList(vm)

    emitBytes(vm, OpInvoke, name)

    emitByte(vm, argCount)
  else:
    emitBytes(vm, OpGetProperty, name)

proc literal(vm: var VM, canAssign: bool) =
  case parser.previous.`type`
  of TokenFalse:
    emitByte(vm, OpFalse)
  of TokenNil:
    emitByte(vm, OpNil)
  of TokenTrue:
    emitByte(vm, OpTrue)
  else:
    discard

proc grouping(vm: var VM, canAssign: bool) =
  expression(vm)

  consume(TokenRightParen, "Expect ')' after expression.")

proc number(vm: var VM, canAssign: bool) =
  var value: float

  discard parseFloat(lexeme(parser.previous), value)

  emitConstant(vm, numberVal(value))

proc `or`(vm: var VM, canAssign: bool) =
  let
    elseJump = emitJump(vm, OpJumpIfFalse)
    endJump = emitJump(vm, OpJump)

  patchJump(elseJump)

  emitByte(vm, OpPop)

  parsePrecedence(vm, PrecOr)

  patchJump(endJump)

proc string(vm: var VM, canAssign: bool) =
  emitConstant(vm, objVal(copyString(vm, parser.previous.start + 1, parser.previous.length - 2)))

proc namedVariable(vm: var VM, name: Token, canAssign: bool) =
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
      arg = identifierConstant(vm, name).int32
      getOp = OpGetGlobal
      setOp = OpSetGlobal

  if canAssign and match(TokenEqual):
    expression(vm)

    emitBytes(vm, setOp, uint8(arg))
  else:
    emitBytes(vm, getOp, uint8(arg))

proc variable(vm: var VM, canAssign: bool) =
  namedVariable(vm, parser.previous, canAssign)

proc syntheticToken(text: cstring): Token =
  result.start = cast[ptr char](text)
  result.length = len(text).int32

proc super(vm: var VM, canAssign: bool) =
  if isNil(currentClass):
    error("Can't use 'super' outside of a class.")
  elif not currentClass.hasSuperclass:
    error("Can't use 'super' in a class with no superclass.")

  consume(TokenDot, "Expect '.' after 'super'.")
  consume(TokenIdentifier, "Expect superclass method name.")

  let name = identifierConstant(vm, parser.previous)

  namedVariable(vm, syntheticToken(cstring"this"), false)

  if match(TokenLeftParen):
    let argCount = argumentList(vm)

    namedVariable(vm, syntheticToken(cstring"super"), false)

    emitBytes(vm, OpSuperInvoke, name)
    emitByte(vm, argCount)
  else:
    namedVariable(vm, syntheticToken(cstring"super"), false)
    emitBytes(vm, OpGetSuper, name)

proc this(vm: var VM, canAssign: bool) =
  if isNil(currentClass):
    error("Can't use 'this' outside of a class.")
    return

  variable(vm, false)

proc unary(vm: var VM, canAssign: bool) =
  let operatorType = parser.previous.`type`

  parsePrecedence(vm, PrecUnary)

  case operatorType
  of TokenBang:
    emitByte(vm, OpNot)
  of TokenMinus:
    emitByte(vm, OpNegate)
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

proc parsePrecedence(vm: var VM, precedence: Precedence) =
  advance()

  let prefixRule = getRule(parser.previous.`type`).prefix

  if isNil(prefixRule):
    error("Expect expression.")
    return

  let canAssign = precedence <= PrecAssignment

  prefixRule(vm, canAssign)

  while precedence <= getRule(parser.current.`type`).precedence:
    advance()

    let infixRule = getRule(parser.previous.`type`).infix

    infixRule(vm, canAssign)

  if canAssign and match(TokenEqual):
    error("Invalid assignment target.")

proc getRule(`type`: TokenType): ptr ParseRule =
  addr rules[ord(`type`)]

proc expression(vm: var VM) =
  parsePrecedence(vm, PrecAssignment)

proc `block`(vm: var VM) =
  while not(check(TokenRightBrace)) and not(check(TokenEof)):
    declaration(vm)

  consume(TokenRightBrace, "Expect '}' after block.")

proc function(vm: var VM, `type`: FunctionType) =
  var compiler: Compiler

  initCompiler(vm, compiler, `type`)

  beginScope()

  consume(TokenLeftParen, "Expect '(' after function name.")

  if not check(TokenRightParen):
    while true:
      inc(current.function.arity)

      if current.function.arity > 255:
        errorAtCurrent("Can't have more than 255 parameters.")

      let constant = parseVariable(vm, "Expect parameter name.")

      defineVariable(vm, constant)

      if not match(TokenComma):
        break

  consume(TokenRightParen, "Expect ')' after parameters.")
  consume(TokenLeftBrace, "Expect '{' before function body.")

  `block`(vm)

  let function = endCompiler(vm)

  emitBytes(vm, OpClosure, makeConstant(vm, objVal(function)))

  for i in 0 ..< function.upvalueCount:
    emitByte(vm, if compiler.upvalues[i].isLocal: 1 else: 0)
    emitByte(vm, compiler.upvalues[i].index)

proc `method`(vm: var VM) =
  consume(TokenIdentifier, "Expect method name.")

  let constant = identifierConstant(vm, parser.previous)

  var `type` = TypeMethod

  if parser.previous.length == 4 and cmpMem(parser.previous.start, cstring"init", 4) == 0:
    `type` = TypeInitializer

  function(vm, `type`)

  emitBytes(vm, OpMethod, constant)

proc classDeclaration(vm: var VM) =
  consume(TokenIdentifier, "Expect class name.")

  let
    className = parser.previous
    nameConstant = identifierConstant(vm, parser.previous)

  declareVariable()

  emitBytes(vm, OpClass, nameConstant)

  defineVariable(vm, nameConstant)

  var classCompiler: ClassCompiler

  classCompiler.hasSuperclass = false
  classCompiler.enclosing = currentClass
  currentClass = addr classCompiler

  if match(TokenLess):
    consume(TokenIdentifier, "Expect superclass name.")

    variable(vm, false)

    if identifiersEqual(className, parser.previous):
      error("A class can't inherit from itself.")

    beginScope()

    addLocal(syntheticToken(cstring"super"))

    defineVariable(vm, 0)

    namedVariable(vm, className, false)

    emitByte(vm, OpInherit)

    classCompiler.hasSuperclass = true

  namedVariable(vm, className, false)

  consume(TokenLeftBrace, "Expect '{' before class body.")

  while not(check(TokenRightBrace)) and not(check(TokenEof)):
    `method`(vm)

  consume(TokenRightBrace, "Expect '}' after class body.")

  emitByte(vm, OpPop)

  if classCompiler.hasSuperclass:
    endScope(vm)

  currentClass = currentClass.enclosing

proc funDeclaration(vm: var VM) =
  let global = parseVariable(vm, "Expect function name.")

  markInitialized()

  function(vm, TypeFunction)

  defineVariable(vm, global)

proc varDeclaration(vm: var VM) =
  let global = parseVariable(vm, "Expect variable name.")

  if match(TokenEqual):
    expression(vm)
  else:
    emitByte(vm, OpNil)

  consume(TokenSemicolon, "Expect ';' after variable declaration.")

  defineVariable(vm, global)

proc expressionStatement(vm: var VM) =
  expression(vm)

  consume(TokenSemicolon, "Expect ';' after expression.")

  emitByte(vm, OpPop)

proc forStatement(vm: var VM) =
  beginScope()

  consume(TokenLeftParen, "Expect '(' after 'for'.")

  if match(TokenSemicolon):
    discard
  elif match(TokenVar):
    varDeclaration(vm)
  else:
    expressionStatement(vm)

  var loopStart = currentChunk().count

  var exitJump = -1'i32

  if not match(TokenSemicolon):
    expression(vm)

    consume(TokenSemicolon, "Expect ';' after loop condition.")

    exitJump = emitJump(vm, OpJumpIfFalse)

    emitByte(vm, OpPop)

  if not match(TokenRightParen):
    let
      bodyJump = emitJump(vm, OpJump)
      incrementStart = currentChunk().count

    expression(vm)

    emitByte(vm, OpPop)

    consume(TokenRightParen, "Expect ')' after for clauses.")

    emitLoop(vm, loopStart)

    loopStart = incrementStart

    patchJump(bodyJump)

  statement(vm)

  emitLoop(vm, loopStart)

  if exitJump != -1:
    patchJump(exitJump)

    emitByte(vm, OpPop)

  endScope(vm)

proc ifStatement(vm: var VM) =
  consume(TokenLeftParen, "Expect '(' after 'if'.")

  expression(vm)

  consume(TokenRightParen, "Expect ')' after condition.")

  let thenJump = emitJump(vm, OpJumpIfFalse)

  emitByte(vm, OpPop)

  statement(vm)

  let elseJump = emitJump(vm, OpJump)

  patchJump(thenJump)

  emitByte(vm, OpPop)

  if match(TokenElse):
    statement(vm)

  patchJump(elseJump)

proc printStatement(vm: var VM) =
  expression(vm)

  consume(TokenSemicolon, "Expect ';' after value.")

  emitByte(vm, OpPrint)

proc returnStatement(vm: var VM) =
  if current.`type` == TypeScript:
    error("Can't return from top-level code.")

  if match(TokenSemicolon):
    emitReturn(vm)
  else:
    if current.`type` == TypeInitializer:
      error("Can't return a value from an initializer.")

    expression(vm)

    consume(TokenSemicolon, "Expect ';' after return value.")

    emitByte(vm, OpReturn)

proc whileStatement(vm: var VM) =
  let loopStart = currentChunk().count

  consume(TokenLeftParen, "Expect '(' after 'while'.")

  expression(vm)

  consume(TokenRightParen, "Expect ')' after condition.")

  let exitJump = emitJump(vm, OpJumpIfFalse)

  emitByte(vm, OpPop)

  statement(vm)

  emitLoop(vm, loopStart)

  patchJump(exitJump)

  emitByte(vm, OpPop)

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

proc declaration(vm: var VM) =
  if match(TokenClass):
    classDeclaration(vm)
  elif match(TokenFun):
    funDeclaration(vm)
  elif match(TokenVar):
    varDeclaration(vm)
  else:
    statement(vm)

  if parser.panicMode:
    synchronize()

proc statement(vm: var VM) =
  if match(TokenPrint):
    printStatement(vm)
  elif match(TokenFor):
    forStatement(vm)
  elif match(TokenIf):
    ifStatement(vm)
  elif match(TokenReturn):
    returnStatement(vm)
  elif match(TokenWhile):
    whileStatement(vm)
  elif match(TokenLeftBrace):
    beginScope()

    `block`(vm)

    endScope(vm)
  else:
    expressionStatement(vm)

proc compile*(vm: var VM, source: var string): ptr ObjFunction =
  initScanner(source)

  var compiler: Compiler

  initCompiler(vm, compiler, TypeScript)

  parser.hadError = false
  parser.panicMode = false

  advance()

  while not match(TokenEof):
    declaration(vm)

  let function = endCompiler(vm)

  return if parser.hadError: nil else: function
