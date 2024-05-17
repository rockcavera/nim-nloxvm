import ./types

import ./private/pointer_arithmetics

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
  result.`type` = TokenError
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

  TokenIdentifier

proc identifierType(): TokenType =
  case scanner.start[]
  of 'a':
    return checkKeyword(1, 2, "nd", TokenAnd)
  of 'c':
    return checkKeyword(1, 4, "lass", TokenClass)
  of 'e':
    return checkKeyword(1, 3, "lse", TokenElse)
  of 'f':
    if scanner.current - scanner.start > 1:
      case scanner.start[1]
      of 'a':
        return checkKeyword(2, 3, "lse", TokenFalse)
      of 'o':
        return checkKeyword(2, 1, "r", TokenFor)
      of 'u':
        return checkKeyword(2, 1, "n", TokenFun)
      else:
        discard
  of 'i':
    return checkKeyword(1, 1, "f", TokenIf)
  of 'n':
    return checkKeyword(1, 2, "il", TokenNil)
  of 'o':
    return checkKeyword(1, 1, "r", TokenOr)
  of 'p':
    return checkKeyword(1, 4, "rint", TokenPrint)
  of 'r':
    return checkKeyword(1, 5, "eturn", TokenReturn)
  of 's':
    return checkKeyword(1, 4, "uper", TokenSuper)
  of 't':
    if scanner.current - scanner.start > 1:
      case scanner.start[1]
      of 'h':
        return checkKeyword(2, 2, "is", TokenThis)
      of 'r':
        return checkKeyword(2, 2, "ue", TokenTrue)
      else:
        discard
  of 'v':
    return checkKeyword(1, 2, "ar", TokenVar)
  of 'w':
    return checkKeyword(1, 4, "hile", TokenWhile)
  else:
    discard

  TokenIdentifier

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

  makeToken(TokenNumber)

proc string(): Token =
  while peek() != '"' and not(isAtEnd()):
    if peek() == '\n':
      scanner.line += 1

    discard advance()

  if isAtEnd():
    return errorToken("Unterminated string.")

  discard advance()

  makeToken(TokenString)

proc scanToken*(): Token =
  skipWhitespace()

  scanner.start = scanner.current

  if isAtEnd():
    return makeToken(TokenEof)

  let c = advance()

  if isAlpha(c):
    return identifier()

  if isDigit(c):
    return number()

  case c
  of '(':
    return makeToken(TokenLeftParen)
  of ')':
    return makeToken(TokenRightParen)
  of '{':
    return makeToken(TokenLeftBrace)
  of '}':
    return makeToken(TokenRightBrace)
  of ';':
    return makeToken(TokenSemicolon)
  of ',':
    return makeToken(TokenComma)
  of '.':
    return makeToken(TokenDot)
  of '-':
    return makeToken(TokenMinus)
  of '+':
    return makeToken(TokenPlus)
  of '/':
    return makeToken(TokenSlash)
  of '*':
    return makeToken(TokenStar)
  of '!':
    return makeToken(if match('='): TokenBangEqual else: TokenBang)
  of '=':
    return makeToken(if match('='): TokenEqualEqual else: TokenEqual)
  of '<':
    return makeToken(if match('='): TokenLessEqual else: TokenLess)
  of '>':
    return makeToken(if match('='): TokenGreaterEqual else: TokenGreater)
  of '"':
    return string()
  else:
    discard

  return errorToken("Unexpected character.")
