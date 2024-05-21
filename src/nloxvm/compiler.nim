import std/parseutils

import ./chunk, ./common, ./object, ./scanner, ./types, ./value_helpers

when defined(debugPrintCode):
  import ./debug

import ./private/pointer_arithmetics

const uint16Max = high(uint16).int32

var currentClass: ptr ClassCompiler = nil

template lexeme(token: Token): openArray[char] =
  toOpenArray(cast[cstring](token.start), 0, token.length - 1)

proc currentChunk(vm: var VM): var Chunk =
  vm.currentCompiler.function.chunk

proc errorAt(parser: var Parser, token: var Token, message: ptr char) =
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

proc error(parser: var Parser, message: ptr char) =
  errorAt(parser, parser.previous, message)

proc error(parser: var Parser, message: string) =
  errorAt(parser, parser.previous, addr message[0])

proc errorAtCurrent(parser: var Parser, message: ptr char) =
  errorAt(parser, parser.current, message)

proc errorAtCurrent(parser: var Parser, message: string) =
  errorAt(parser, parser.current, addr message[0])

proc advance(parser: var Parser) =
  parser.previous = parser.current

  while true:
    parser.current = scanToken()

    if parser.current.`type` != TokenError:
      break

    errorAtCurrent(parser, parser.current.start)

proc consume(parser: var Parser, `type`: TokenType, message: string) =
  if parser.current.`type` == `type`:
    advance(parser)
    return

  errorAtCurrent(parser, addr message[0])

proc check(parser: var Parser, `type`: TokenType): bool =
  parser.current.`type` == `type`

proc match(parser: var Parser, `type`: TokenType): bool =
  if not check(parser, `type`):
    return false

  advance(parser)

  true

proc emitByte(vm: var VM, parser: var Parser, `byte`: uint8) =
  writeChunk(vm, currentChunk(vm), `byte`, parser.previous.line)

template emitByte(vm: var VM, parser: var Parser, opCode: OpCode) =
  emitByte(vm, parser, uint8(opCode))

proc emitBytes(vm: var VM, parser: var Parser, byte1: uint8, byte2: uint8) =
  emitByte(vm, parser, byte1)
  emitByte(vm, parser, byte2)

template emitBytes(vm: var VM, parser: var Parser, opCode1: OpCode, opCode2: OpCode) =
  emitBytes(vm, parser, uint8(opCode1), uint8(opCode2))

template emitBytes(vm: var VM, parser: var Parser, opCode: OpCode, `byte`: uint8) =
  emitBytes(vm, parser, uint8(opCode), `byte`)

proc emitLoop(vm: var VM, parser: var Parser, loopStart: int32) =
  emitByte(vm, parser, OpLoop)

  let offset = currentChunk(vm).count - loopStart + 2

  if offset > uint16Max:
    error(parser, "Loop body too large.")

  emitByte(vm, parser, uint8((offset shr 8) and 0xff))
  emitByte(vm, parser, uint8(offset and 0xff))

proc emitJump(vm: var VM, parser: var Parser, instruction: uint8): int32 =
  emitByte(vm, parser, instruction)
  emitByte(vm, parser, 0xff)
  emitByte(vm, parser, 0xff)

  currentChunk(vm).count - 2

template emitJump(vm: var VM, parser: var Parser, instruction: OpCode): int32 =
  emitJump(vm, parser, uint8(instruction))

proc emitReturn(vm: var VM, parser: var Parser) =
  if vm.currentCompiler.`type` == TypeInitializer:
    emitBytes(vm, parser, OpGetLocal, 0)
  else:
    emitByte(vm, parser, OpNil)

  emitByte(vm, parser, OpReturn)

proc makeConstant(vm: var VM, parser: var Parser, value: Value): uint8 =
  const uint8Max = high(uint8).int32

  let constant = addConstant(vm, currentChunk(vm), value)

  if constant > uint8Max:
    error(parser, "Too many constants in one chunk.")
    return 0'u8

  uint8(constant)

proc emitConstant(vm: var VM, parser: var Parser, value: Value) =
  emitBytes(vm, parser, OpConstant, makeConstant(vm, parser, value))

proc patchJump(vm: var VM, parser: var Parser, offset: int32) =
  let jump = currentChunk(vm).count - offset - 2

  if jump > uint16Max:
    error(parser, "Too much code to jump over.")

  currentChunk(vm).code[offset] = uint8((jump shr 8) and 0xff)
  currentChunk(vm).code[offset + 1] = uint8(jump and 0xff)

proc initCompiler(vm: var VM, compiler: var Compiler, parser: var Parser, `type`: FunctionType) =
  compiler.enclosing = vm.currentCompiler
  compiler.function = nil
  compiler.`type` = `type`
  compiler.localCount = 0
  compiler.scopeDepth = 0
  compiler.function = newFunction(vm)
  vm.currentCompiler = addr compiler

  if `type` != TypeScript:
    vm.currentCompiler.function.name = copyString(vm, parser.previous.start, parser.previous.length)

  var local = addr vm.currentCompiler.locals[vm.currentCompiler.localCount]

  inc(vm.currentCompiler.localCount)

  local.depth = 0
  local.isCaptured = false

  if `type` != TypeFunction:
    local.name.start = cast[ptr char](cstring"this")
    local.name.length = 4
  else:
    local.name.start = cast[ptr char](cstring"")
    local.name.length = 0

proc endCompiler(vm: var VM, parser: var Parser): ptr ObjFunction =
  emitReturn(vm, parser)

  result = vm.currentCompiler.function

  when defined(debugPrintCode):
    if not parser.hadError:
      disassembleChunk(currentChunk(vm),
                       if not isNil(result.name): result.name.chars
                       else: cast[ptr char](cstring"<script>"))

  vm.currentCompiler = vm.currentCompiler.enclosing

proc beginScope(vm: var VM) =
  inc(vm.currentCompiler.scopeDepth)

proc endScope(vm: var VM, parser: var Parser) =
  dec(vm.currentCompiler.scopeDepth)

  while (vm.currentCompiler.localCount > 0) and (vm.currentCompiler.locals[vm.currentCompiler.localCount - 1].depth > vm.currentCompiler.scopeDepth):
    if vm.currentCompiler.locals[vm.currentCompiler.localCount - 1].isCaptured:
      emitByte(vm, parser, OpCloseUpvalue)
    else:
      emitByte(vm, parser, OpPop)

    dec(vm.currentCompiler.localCount)

proc expression(vm: var VM, parser: var Parser)
proc statement(vm: var VM, parser: var Parser)
proc declaration(vm: var VM, parser: var Parser)
proc getRule(parser: var Parser, `type`: TokenType): ptr ParseRule
proc parsePrecedence(vm: var VM, parser: var Parser, precedence: Precedence)

proc identifierConstant(vm: var VM, parser: var Parser, name: Token): uint8 =
  makeConstant(vm, parser, objVal(copyString(vm, name.start, name.length)))

proc identifiersEqual(a: Token, b: Token): bool =
  if a.length != b.length:
    return false

  cmpMem(a.start, b.start, a.length) == 0

proc resolveLocal(compiler: ptr Compiler, parser: var Parser, name: Token): int32 =
  for i in countdown(compiler.localCount - 1, 0):
    let local = addr compiler.locals[i]

    if identifiersEqual(name, local.name):
      if local.depth == -1:
        error(parser, "Can't read local variable in its own initializer.")

      return i

  -1

proc addUpvalue(compiler: ptr Compiler, parser: var Parser, index: uint8, isLocal: bool): int32 =
  let upvalueCount = compiler.function.upvalueCount

  for i in 0'i32 ..< upvalueCount:
    let upvalue = compiler.upvalues[i]

    if upvalue.index == index and upvalue.isLocal == isLocal:
      return i

  if upvalueCount == uint8Count:
    error(parser, "Too many closure variables in function.")
    return 0

  compiler.upvalues[upvalueCount].isLocal = isLocal
  compiler.upvalues[upvalueCount].index = index

  inc(compiler.function.upvalueCount)

  return upvalueCount

proc resolveUpvalue(compiler: ptr Compiler, parser: var Parser, name: Token): int32 =
  if isNil(compiler.enclosing):
    return -1

  let local = resolveLocal(compiler.enclosing, parser, name)

  if local != -1:
    compiler.enclosing.locals[local].isCaptured = true
    return addUpvalue(compiler, parser, uint8(local), true)

  let upvalue = resolveUpvalue(compiler.enclosing, parser, name)

  if upvalue != -1:
    return addUpvalue(compiler, parser, uint8(upvalue), false)

  -1

proc addLocal(vm: var VM, parser: var Parser, name: Token) =
  if vm.currentCompiler.localCount == uint8Count:
    error(parser, "Too many local variables in function.")
    return

  let tmp = vm.currentCompiler.localCount

  inc(vm.currentCompiler.localCount)

  var local = addr vm.currentCompiler.locals[tmp]

  local.name = name
  local.depth = -1
  local.isCaptured = false

proc declareVariable(vm: var VM, parser: var Parser) =
  if vm.currentCompiler.scopeDepth == 0:
    return

  let name = parser.previous

  for i in countdown(vm.currentCompiler.localCount  - 1, 0):
    let local = addr vm.currentCompiler.locals[i]

    if (local.depth != -1) and (local.depth < vm.currentCompiler.scopeDepth):
      break

    if identifiersEqual(name, local.name):
      error(parser, "Already a variable with this name in this scope.")

  addLocal(vm, parser, name)

proc parseVariable(vm: var VM, parser: var Parser, errorMessage: string): uint8 =
  consume(parser, TokenIdentifier, errorMessage)

  declareVariable(vm, parser)

  if vm.currentCompiler.scopeDepth > 0:
    return 0

  identifierConstant(vm, parser, parser.previous)

proc markInitialized(vm: var VM) =
  if vm.currentCompiler.scopeDepth == 0:
    return

  vm.currentCompiler.locals[vm.currentCompiler.localCount - 1].depth = vm.currentCompiler.scopeDepth

proc defineVariable(vm: var VM, parser: var Parser, global: uint8) =
  if vm.currentCompiler.scopeDepth > 0:
    markInitialized(vm)
    return

  emitBytes(vm, parser, OpDefineGlobal, global)

proc argumentList(vm: var VM, parser: var Parser): uint8 =
  if not check(parser, TokenRightParen):
    while true:
      expression(vm, parser)

      if result == 255:
        error(parser, "Can't have more than 255 arguments.")

      inc(result)

      if not match(parser, TokenComma):
        break

  consume(parser, TokenRightParen, "Expect ')' after arguments.")

proc `and`(vm: var VM, parser: var Parser, canAssign: bool) =
  let endJump = emitJump(vm, parser, OpJumpIfFalse)

  emitByte(vm, parser, OpPop)

  parsePrecedence(vm, parser, PrecAnd)

  patchJump(vm, parser, endJump)

proc binary(vm: var VM, parser: var Parser, canAssign: bool) =
  let
    operatorType = parser.previous.`type`
    rule = getRule(parser, operatorType)

  parsePrecedence(vm, parser, Precedence(ord(rule.precedence) + 1))

  case operatorType
  of TokenBangEqual:
    emitBytes(vm, parser, OpEqual, OpNot)
  of TokenEqualEqual:
    emitByte(vm, parser, OpEqual)
  of TokenGreater:
    emitByte(vm, parser, OpGreater)
  of TokenGreaterEqual:
    emitBytes(vm, parser, OpLess, OpNot)
  of TokenLess:
    emitByte(vm, parser, OpLess)
  of TokenLessEqual:
    emitBytes(vm, parser, OpGreater, OpNot)
  of TokenPlus:
    emitByte(vm, parser, OpAdd)
  of TokenMinus:
    emitByte(vm, parser, OpSubtract)
  of TokenStar:
    emitByte(vm, parser, OpMultiply)
  of TokenSlash:
    emitByte(vm, parser, OpDivide)
  else:
    discard

proc call(vm: var VM, parser: var Parser, canAssign: bool) =
  let argCount = argumentList(vm, parser)

  emitBytes(vm, parser, OpCall, argCount)

proc dot(vm: var VM, parser: var Parser, canAssign: bool) =
  consume(parser, TokenIdentifier, "Expect property name after '.'.")

  let name = identifierConstant(vm, parser, parser.previous)

  if canAssign and match(parser, TokenEqual):
    expression(vm, parser)

    emitBytes(vm, parser, OpSetProperty, name)
  elif match(parser, TokenLeftParen):
    let argCount = argumentList(vm, parser)

    emitBytes(vm, parser, OpInvoke, name)

    emitByte(vm, parser, argCount)
  else:
    emitBytes(vm, parser, OpGetProperty, name)

proc literal(vm: var VM, parser: var Parser, canAssign: bool) =
  case parser.previous.`type`
  of TokenFalse:
    emitByte(vm, parser, OpFalse)
  of TokenNil:
    emitByte(vm, parser, OpNil)
  of TokenTrue:
    emitByte(vm, parser, OpTrue)
  else:
    discard

proc grouping(vm: var VM, parser: var Parser, canAssign: bool) =
  expression(vm, parser)

  consume(parser, TokenRightParen, "Expect ')' after expression.")

proc number(vm: var VM, parser: var Parser, canAssign: bool) =
  var value: float

  discard parseFloat(lexeme(parser.previous), value)

  emitConstant(vm, parser, numberVal(value))

proc `or`(vm: var VM, parser: var Parser, canAssign: bool) =
  let
    elseJump = emitJump(vm, parser, OpJumpIfFalse)
    endJump = emitJump(vm, parser, OpJump)

  patchJump(vm, parser, elseJump)

  emitByte(vm, parser, OpPop)

  parsePrecedence(vm, parser, PrecOr)

  patchJump(vm, parser, endJump)

proc string(vm: var VM, parser: var Parser, canAssign: bool) =
  emitConstant(vm, parser, objVal(copyString(vm, parser.previous.start + 1, parser.previous.length - 2)))

proc namedVariable(vm: var VM, parser: var Parser, name: Token, canAssign: bool) =
  var
    getOp: OpCode
    setOp: OpCode
    arg = resolveLocal(vm.currentCompiler, parser, name)

  if arg != -1:
    getOp = OpGetLocal
    setOp = OpSetLocal
  else:
    arg = resolveUpvalue(vm.currentCompiler, parser, name)

    if arg != -1:
      getOp = OpGetUpvalue
      setOp = OpSetUpvalue
    else:
      arg = identifierConstant(vm, parser, name).int32
      getOp = OpGetGlobal
      setOp = OpSetGlobal

  if canAssign and match(parser, TokenEqual):
    expression(vm, parser)

    emitBytes(vm, parser, setOp, uint8(arg))
  else:
    emitBytes(vm, parser, getOp, uint8(arg))

proc variable(vm: var VM, parser: var Parser, canAssign: bool) =
  namedVariable(vm, parser, parser.previous, canAssign)

proc syntheticToken(text: cstring): Token =
  result.start = cast[ptr char](text)
  result.length = len(text).int32

proc super(vm: var VM, parser: var Parser, canAssign: bool) =
  if isNil(currentClass):
    error(parser, "Can't use 'super' outside of a class.")
  elif not currentClass.hasSuperclass:
    error(parser, "Can't use 'super' in a class with no superclass.")

  consume(parser, TokenDot, "Expect '.' after 'super'.")
  consume(parser, TokenIdentifier, "Expect superclass method name.")

  let name = identifierConstant(vm, parser, parser.previous)

  namedVariable(vm, parser, syntheticToken(cstring"this"), false)

  if match(parser, TokenLeftParen):
    let argCount = argumentList(vm, parser)

    namedVariable(vm, parser, syntheticToken(cstring"super"), false)

    emitBytes(vm, parser, OpSuperInvoke, name)
    emitByte(vm, parser, argCount)
  else:
    namedVariable(vm, parser, syntheticToken(cstring"super"), false)
    emitBytes(vm, parser, OpGetSuper, name)

proc this(vm: var VM, parser: var Parser, canAssign: bool) =
  if isNil(currentClass):
    error(parser, "Can't use 'this' outside of a class.")
    return

  variable(vm, parser, false)

proc unary(vm: var VM, parser: var Parser, canAssign: bool) =
  let operatorType = parser.previous.`type`

  parsePrecedence(vm, parser, PrecUnary)

  case operatorType
  of TokenBang:
    emitByte(vm, parser, OpNot)
  of TokenMinus:
    emitByte(vm, parser, OpNegate)
  else:
    discard

proc initRules(): array[40, ParseRule] =
  [ParseRule(prefix: grouping, infix: call, precedence: PrecCall),   # TokenLeftParen
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
  ParseRule(prefix: nil, infix: nil, precedence: PrecNone)]          # TokenEof

proc parsePrecedence(vm: var VM, parser: var Parser, precedence: Precedence) =
  advance(parser)

  let prefixRule = getRule(parser, parser.previous.`type`).prefix

  if isNil(prefixRule):
    error(parser, "Expect expression.")
    return

  let canAssign = precedence <= PrecAssignment

  prefixRule(vm, parser, canAssign)

  while precedence <= getRule(parser, parser.current.`type`).precedence:
    advance(parser)

    let infixRule = getRule(parser, parser.previous.`type`).infix

    infixRule(vm, parser, canAssign)

  if canAssign and match(parser, TokenEqual):
    error(parser, "Invalid assignment target.")

proc getRule(parser: var Parser, `type`: TokenType): ptr ParseRule =
  addr parser.rules[ord(`type`)]

proc expression(vm: var VM, parser: var Parser) =
  parsePrecedence(vm, parser, PrecAssignment)

proc `block`(vm: var VM, parser: var Parser) =
  while not(check(parser, TokenRightBrace)) and not(check(parser, TokenEof)):
    declaration(vm, parser)

  consume(parser, TokenRightBrace, "Expect '}' after block.")

proc function(vm: var VM, parser: var Parser, `type`: FunctionType) =
  var compiler: Compiler

  initCompiler(vm, compiler, parser, `type`)

  beginScope(vm)

  consume(parser, TokenLeftParen, "Expect '(' after function name.")

  if not check(parser, TokenRightParen):
    while true:
      inc(vm.currentCompiler.function.arity)

      if vm.currentCompiler.function.arity > 255:
        errorAtCurrent(parser, "Can't have more than 255 parameters.")

      let constant = parseVariable(vm, parser, "Expect parameter name.")

      defineVariable(vm, parser, constant)

      if not match(parser, TokenComma):
        break

  consume(parser, TokenRightParen, "Expect ')' after parameters.")
  consume(parser, TokenLeftBrace, "Expect '{' before function body.")

  `block`(vm, parser)

  let function = endCompiler(vm, parser)

  emitBytes(vm, parser, OpClosure, makeConstant(vm, parser, objVal(function)))

  for i in 0 ..< function.upvalueCount:
    emitByte(vm, parser, if compiler.upvalues[i].isLocal: 1 else: 0)
    emitByte(vm, parser, compiler.upvalues[i].index)

proc `method`(vm: var VM, parser: var Parser) =
  consume(parser, TokenIdentifier, "Expect method name.")

  let constant = identifierConstant(vm, parser, parser.previous)

  var `type` = TypeMethod

  if parser.previous.length == 4 and cmpMem(parser.previous.start, cstring"init", 4) == 0:
    `type` = TypeInitializer

  function(vm, parser, `type`)

  emitBytes(vm, parser, OpMethod, constant)

proc classDeclaration(vm: var VM, parser: var Parser) =
  consume(parser, TokenIdentifier, "Expect class name.")

  let
    className = parser.previous
    nameConstant = identifierConstant(vm, parser, parser.previous)

  declareVariable(vm, parser)

  emitBytes(vm, parser, OpClass, nameConstant)

  defineVariable(vm, parser, nameConstant)

  var classCompiler: ClassCompiler

  classCompiler.hasSuperclass = false
  classCompiler.enclosing = currentClass
  currentClass = addr classCompiler

  if match(parser, TokenLess):
    consume(parser, TokenIdentifier, "Expect superclass name.")

    variable(vm, parser, false)

    if identifiersEqual(className, parser.previous):
      error(parser, "A class can't inherit from itself.")

    beginScope(vm)

    addLocal(vm, parser, syntheticToken(cstring"super"))

    defineVariable(vm, parser, 0)

    namedVariable(vm, parser, className, false)

    emitByte(vm, parser, OpInherit)

    classCompiler.hasSuperclass = true

  namedVariable(vm, parser, className, false)

  consume(parser, TokenLeftBrace, "Expect '{' before class body.")

  while not(check(parser, TokenRightBrace)) and not(check(parser, TokenEof)):
    `method`(vm, parser)

  consume(parser, TokenRightBrace, "Expect '}' after class body.")

  emitByte(vm, parser, OpPop)

  if classCompiler.hasSuperclass:
    endScope(vm, parser)

  currentClass = currentClass.enclosing

proc funDeclaration(vm: var VM, parser: var Parser) =
  let global = parseVariable(vm, parser, "Expect function name.")

  markInitialized(vm)

  function(vm, parser, TypeFunction)

  defineVariable(vm, parser, global)

proc varDeclaration(vm: var VM, parser: var Parser) =
  let global = parseVariable(vm, parser, "Expect variable name.")

  if match(parser, TokenEqual):
    expression(vm, parser)
  else:
    emitByte(vm, parser, OpNil)

  consume(parser, TokenSemicolon, "Expect ';' after variable declaration.")

  defineVariable(vm, parser, global)

proc expressionStatement(vm: var VM, parser: var Parser) =
  expression(vm, parser)

  consume(parser, TokenSemicolon, "Expect ';' after expression.")

  emitByte(vm, parser, OpPop)

proc forStatement(vm: var VM, parser: var Parser) =
  beginScope(vm)

  consume(parser, TokenLeftParen, "Expect '(' after 'for'.")

  if match(parser, TokenSemicolon):
    discard
  elif match(parser, TokenVar):
    varDeclaration(vm, parser)
  else:
    expressionStatement(vm, parser)

  var loopStart = currentChunk(vm).count

  var exitJump = -1'i32

  if not match(parser, TokenSemicolon):
    expression(vm, parser)

    consume(parser, TokenSemicolon, "Expect ';' after loop condition.")

    exitJump = emitJump(vm, parser, OpJumpIfFalse)

    emitByte(vm, parser, OpPop)

  if not match(parser, TokenRightParen):
    let
      bodyJump = emitJump(vm, parser, OpJump)
      incrementStart = currentChunk(vm).count

    expression(vm, parser)

    emitByte(vm, parser, OpPop)

    consume(parser, TokenRightParen, "Expect ')' after for clauses.")

    emitLoop(vm, parser, loopStart)

    loopStart = incrementStart

    patchJump(vm, parser, bodyJump)

  statement(vm, parser)

  emitLoop(vm, parser, loopStart)

  if exitJump != -1:
    patchJump(vm, parser, exitJump)

    emitByte(vm, parser, OpPop)

  endScope(vm, parser)

proc ifStatement(vm: var VM, parser: var Parser) =
  consume(parser, TokenLeftParen, "Expect '(' after 'if'.")

  expression(vm, parser)

  consume(parser, TokenRightParen, "Expect ')' after condition.")

  let thenJump = emitJump(vm, parser, OpJumpIfFalse)

  emitByte(vm, parser, OpPop)

  statement(vm, parser)

  let elseJump = emitJump(vm, parser, OpJump)

  patchJump(vm, parser, thenJump)

  emitByte(vm, parser, OpPop)

  if match(parser, TokenElse):
    statement(vm, parser)

  patchJump(vm, parser, elseJump)

proc printStatement(vm: var VM, parser: var Parser) =
  expression(vm, parser)

  consume(parser, TokenSemicolon, "Expect ';' after value.")

  emitByte(vm, parser, OpPrint)

proc returnStatement(vm: var VM, parser: var Parser) =
  if vm.currentCompiler.`type` == TypeScript:
    error(parser, "Can't return from top-level code.")

  if match(parser, TokenSemicolon):
    emitReturn(vm, parser)
  else:
    if vm.currentCompiler.`type` == TypeInitializer:
      error(parser, "Can't return a value from an initializer.")

    expression(vm, parser)

    consume(parser, TokenSemicolon, "Expect ';' after return value.")

    emitByte(vm, parser, OpReturn)

proc whileStatement(vm: var VM, parser: var Parser) =
  let loopStart = currentChunk(vm).count

  consume(parser, TokenLeftParen, "Expect '(' after 'while'.")

  expression(vm, parser)

  consume(parser, TokenRightParen, "Expect ')' after condition.")

  let exitJump = emitJump(vm, parser, OpJumpIfFalse)

  emitByte(vm, parser, OpPop)

  statement(vm, parser)

  emitLoop(vm, parser, loopStart)

  patchJump(vm, parser, exitJump)

  emitByte(vm, parser, OpPop)

proc synchronize(parser: var Parser) =
  parser.panicMode = false

  while parser.current.`type` != TokenEof:
    if parser.previous.`type` == TokenSemicolon:
      return

    case parser.current.`type`:
    of TokenClass, TokenFun, TokenVar, TokenFor, TokenIf, TokenWhile, TokenPrint, TokenReturn:
      return
    else:
      discard

    advance(parser)

proc declaration(vm: var VM, parser: var Parser) =
  if match(parser, TokenClass):
    classDeclaration(vm, parser)
  elif match(parser, TokenFun):
    funDeclaration(vm, parser)
  elif match(parser, TokenVar):
    varDeclaration(vm, parser)
  else:
    statement(vm, parser)

  if parser.panicMode:
    synchronize(parser)

proc statement(vm: var VM, parser: var Parser) =
  if match(parser, TokenPrint):
    printStatement(vm, parser)
  elif match(parser, TokenFor):
    forStatement(vm, parser)
  elif match(parser, TokenIf):
    ifStatement(vm, parser)
  elif match(parser, TokenReturn):
    returnStatement(vm, parser)
  elif match(parser, TokenWhile):
    whileStatement(vm, parser)
  elif match(parser, TokenLeftBrace):
    beginScope(vm)

    `block`(vm, parser)

    endScope(vm, parser)
  else:
    expressionStatement(vm, parser)

proc compile*(vm: var VM, source: var string): ptr ObjFunction =
  initScanner(source)

  var
    compiler: Compiler
    parser: Parser

  initCompiler(vm, compiler, parser, TypeScript)

  parser.rules = initRules()
  parser.hadError = false
  parser.panicMode = false

  advance(parser)

  while not match(parser, TokenEof):
    declaration(vm, parser)

  let function = endCompiler(vm, parser)

  return if parser.hadError: nil else: function
