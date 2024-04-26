import ./private/pointer_arithmetics

type
  TokenType* = enum
    # Single-character tokens.
    TOKEN_LEFT_PAREN,
    TOKEN_RIGHT_PAREN,
    TOKEN_LEFT_BRACE,
    TOKEN_RIGHT_BRACE,
    TOKEN_COMMA,
    TOKEN_DOT,
    TOKEN_MINUS,
    TOKEN_PLUS,
    TOKEN_SEMICOLON,
    TOKEN_SLASH,
    TOKEN_STAR,
    # One or two character tokens.
    TOKEN_BANG,
    TOKEN_BANG_EQUAL,
    TOKEN_EQUAL,
    TOKEN_EQUAL_EQUAL,
    TOKEN_GREATER,
    TOKEN_GREATER_EQUAL,
    TOKEN_LESS,
    TOKEN_LESS_EQUAL,
    # Literals.
    TOKEN_IDENTIFIER,
    TOKEN_STRING,
    TOKEN_NUMBER,
    # Keywords.
    TOKEN_AND,
    TOKEN_CLASS,
    TOKEN_ELSE,
    TOKEN_FALSE,
    TOKEN_FOR,
    TOKEN_FUN,
    TOKEN_IF,
    TOKEN_NIL,
    TOKEN_OR,
    TOKEN_PRINT,
    TOKEN_RETURN,
    TOKEN_SUPER,
    TOKEN_THIS,
    TOKEN_TRUE,
    TOKEN_VAR,
    TOKEN_WHILE,

    TOKEN_ERROR,
    TOKEN_EOF

  Token* = object
    `type`*: TokenType
    start*: ptr char
    length*: int32
    line*: int32

  Scanner = object
    start: ptr char
    current: ptr char
    line: int32

var scanner: Scanner

proc initScanner*(source: var string) =
  scanner.start = addr source[0]
  scanner.current = addr source[0]
  scanner.line = 1

proc isAlpha(c: char): bool =
  (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'

proc isDigit(c: char): bool =
  c >= '0' and c <= '9'

proc isAtEnd(): bool =
  scanner.current[] == '\0'

proc advance(): char =
  result = scanner.current[]
  scanner.current += 1

proc peek(): char =
  scanner.current[]

proc peekNext(): char =
  if isAtEnd():
    return '\0'

  scanner.current[1]

proc match(expected: char): bool =
  if isAtEnd():
    return false

  if scanner.current[] != expected:
    return false

  scanner.current += 1

  return true

proc makeToken(`type`: TokenType): Token =
  result.`type` = `type`
  result.start = scanner.start
  result.length = int32(scanner.current - scanner.start)
  result.line = scanner.line

proc errorToken(message: string): Token =
  result.`type` = TOKEN_ERROR
  result.start = addr message[0]
  result.length = len(message).int32
  result.line = scanner.line

proc skipWhitespace() =
  while true:
    let c = peek()

    case c
    of ' ', '\r', '\t':
      discard advance()
    of '\n':
      scanner.line += 1
      discard advance()
    of '/':
      if peekNext() == '/':
        while peek() != '\n' and not(isAtEnd()):
          discard advance()
      else:
        return
    else:
      return

proc checkKeyword(start: int32, length: int32, rest: string, `type`: TokenType): TokenType =
  if (scanner.current - scanner.start) == (start + length) and cmpMem(scanner.start + start, cstring(rest), length) == 0:
    return `type`

  TOKEN_IDENTIFIER

proc identifierType(): TokenType =
  case scanner.start[]
  of 'a':
    return checkKeyword(1, 2, "nd", TOKEN_AND)
  of 'c':
    return checkKeyword(1, 4, "lass", TOKEN_CLASS)
  of 'e':
    return checkKeyword(1, 3, "lse", TOKEN_ELSE)
  of 'f':
    if scanner.current - scanner.start > 1:
      case scanner.start[1]
      of 'a':
        return checkKeyword(2, 3, "lse", TOKEN_FALSE)
      of 'o':
        return checkKeyword(2, 1, "r", TOKEN_FOR)
      of 'u':
        return checkKeyword(2, 1, "n", TOKEN_FUN)
      else:
        discard
  of 'i':
    return checkKeyword(1, 1, "f", TOKEN_IF)
  of 'n':
    return checkKeyword(1, 2, "il", TOKEN_NIL)
  of 'o':
    return checkKeyword(1, 1, "r", TOKEN_OR)
  of 'p':
    return checkKeyword(1, 4, "rint", TOKEN_PRINT)
  of 'r':
    return checkKeyword(1, 5, "eturn", TOKEN_RETURN)
  of 's':
    return checkKeyword(1, 4, "uper", TOKEN_SUPER)
  of 't':
    if scanner.current - scanner.start > 1:
      case scanner.start[1]
      of 'h':
        return checkKeyword(2, 2, "is", TOKEN_THIS)
      of 'r':
        return checkKeyword(2, 2, "ue", TOKEN_TRUE)
      else:
        discard
  of 'v':
    return checkKeyword(1, 2, "ar", TOKEN_VAR)
  of 'w':
    return checkKeyword(1, 4, "hile", TOKEN_WHILE)
  else:
    discard

  TOKEN_IDENTIFIER

proc identifier(): Token =
  while isAlpha(peek()) or isDigit(peek()):
    discard advance()

  makeToken(identifierType())

proc number(): Token =
  while isDigit(peek()):
    discard advance()

  if peek() == '.' and isDigit(peekNext()):
    discard advance()

    while isDigit(peek()):
      discard advance()

  makeToken(TOKEN_NUMBER)

proc string(): Token =
  while peek() != '"' and not(isAtEnd()):
    if peek() == '\n':
      scanner.line += 1

    discard advance()

  if isAtEnd():
    return errorToken("Unterminated string.")

  discard advance()

  makeToken(TOKEN_STRING)

proc scanToken*(): Token =
  skipWhitespace()

  scanner.start = scanner.current

  if isAtEnd():
    return makeToken(TOKEN_EOF)

  let c = advance()

  if isAlpha(c):
    return identifier()

  if isDigit(c):
    return number()

  case c
  of '(':
    return makeToken(TOKEN_LEFT_PAREN)
  of ')':
    return makeToken(TOKEN_RIGHT_PAREN)
  of '{':
    return makeToken(TOKEN_LEFT_BRACE)
  of '}':
    return makeToken(TOKEN_RIGHT_BRACE)
  of ';':
    return makeToken(TOKEN_SEMICOLON)
  of ',':
    return makeToken(TOKEN_COMMA)
  of '.':
    return makeToken(TOKEN_DOT)
  of '-':
    return makeToken(TOKEN_MINUS)
  of '+':
    return makeToken(TOKEN_PLUS)
  of '/':
    return makeToken(TOKEN_SLASH)
  of '*':
    return makeToken(TOKEN_STAR)
  of '!':
    return makeToken(if match('='): TOKEN_BANG_EQUAL else: TOKEN_BANG)
  of '=':
    return makeToken(if match('='): TOKEN_EQUAL_EQUAL else: TOKEN_EQUAL)
  of '<':
    return makeToken(if match('='): TOKEN_LESS_EQUAL else: TOKEN_LESS)
  of '>':
    return makeToken(if match('='): TOKEN_GREATER_EQUAL else: TOKEN_GREATER)
  of '"':
    return string()
  else:
    discard

  return errorToken("Unexpected character.")
