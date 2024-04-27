import std/[parseutils, strformat]

import ./chunk, ./object, ./scanner, ./value

when defined(DEBUG_PRINT_CODE):
  import ./debug

import ./private/pointer_arithmetics

type
  Parser = object
    current: Token
    previous: Token
    hadError: bool
    panicMode: bool

  Precedence = enum
    PREC_NONE,
    PREC_ASSIGNMENT,  # =
    PREC_OR,          # or
    PREC_AND,         # and
    PREC_EQUALITY,    # == !=
    PREC_COMPARISON,  # < > <= >=
    PREC_TERM,        # + -
    PREC_FACTOR,      # * /
    PREC_UNARY,       # ! -
    PREC_CALL,        # . ()
    PREC_PRIMARY

  ParseFn = proc() {.nimcall.}

  ParseRule = object
    prefix: ParseFn
    infix: ParseFn
    precedence: Precedence

var
  parser: Parser
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
    write(stderr, fmt" at '{lexeme(token)}'")

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

proc endCompiler() =
  emitReturn()

  when defined(DEBUG_PRINT_CODE):
    if not parser.hadError:
      disassembleChunk(currentChunk(), "code")

proc expression()
proc getRule(`type`: TokenType): ptr ParseRule
proc parsePrecedence(precedence: Precedence)

proc binary() =
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

proc literal() =
  case parser.previous.`type`
  of TOKEN_FALSE:
    emitByte(OP_FALSE)
  of TOKEN_NIL:
    emitByte(OP_NIL)
  of TOKEN_TRUE:
    emitByte(OP_TRUE)
  else:
    discard

proc grouping() =
  expression()

  consume(TOKEN_RIGHT_PAREN, "Expect ')' after expression.")

proc number() =
  var value: float

  discard parseFloat(lexeme(parser.previous), value)

  emitConstant(numberVal(value))

proc string() =
  emitConstant(objVal(cast[ptr Obj](copyString(parser.previous.start + 1, parser.previous.length - 2))))

proc unary() =
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
  ParseRule(prefix: nil, infix: nil, precedence: PREC_NONE),      # TOKEN_IDENTIFIER
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

  prefixRule()

  while precedence <= getRule(parser.current.`type`).precedence:
    advance()

    let infixRule = getRule(parser.previous.`type`).infix

    infixRule()

proc getRule(`type`: TokenType): ptr ParseRule =
  addr rules[ord(`type`)]

proc expression() =
  parsePrecedence(PREC_ASSIGNMENT)

proc compile*(source: var string, chunk: var Chunk): bool =
  initScanner(source)

  compilingChunk = addr chunk

  advance()

  expression()

  consume(TOKEN_EOF, "Expect end of expression.")

  endCompiler()

  not parser.hadError
