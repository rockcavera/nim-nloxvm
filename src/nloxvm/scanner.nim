import ./types

import ./private/pointer_arithmetics

proc initScanner*(source: var string): Scanner =
  result.start = addr source[0]
  result.current = addr source[0]
  result.line = 1

proc isAlpha(c: char): bool =
  (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'

proc isDigit(c: char): bool =
  c >= '0' and c <= '9'

proc isAtEnd(scanner: var Scanner): bool =
  scanner.current[] == '\0'

proc advance(scanner: var Scanner): char =
  result = scanner.current[]
  scanner.current += 1

proc peek(scanner: var Scanner): char =
  scanner.current[]

proc peekNext(scanner: var Scanner): char =
  if isAtEnd(scanner):
    return '\0'

  scanner.current[1]

proc match(scanner: var Scanner, expected: char): bool =
  if isAtEnd(scanner):
    return false

  if scanner.current[] != expected:
    return false

  scanner.current += 1

  return true

proc makeToken(scanner: var Scanner, `type`: TokenType): Token =
  result.`type` = `type`
  result.start = scanner.start
  result.length = int32(scanner.current - scanner.start)
  result.line = scanner.line

proc errorToken(scanner: var Scanner, message: string): Token =
  result.`type` = TokenError
  result.start = addr message[0]
  result.length = len(message).int32
  result.line = scanner.line

proc skipWhitespace(scanner: var Scanner) =
  while true:
    let c = peek(scanner)

    case c
    of ' ', '\r', '\t':
      discard advance(scanner)
    of '\n':
      scanner.line += 1
      discard advance(scanner)
    of '/':
      if peekNext(scanner) == '/':
        while peek(scanner) != '\n' and not(isAtEnd(scanner)):
          discard advance(scanner)
      else:
        return
    else:
      return

proc checkKeyword(scanner: var Scanner, start: int32, length: int32, rest: string, `type`: TokenType): TokenType =
  if (scanner.current - scanner.start) == (start + length) and cmpMem(scanner.start + start, cstring(rest), length) == 0:
    return `type`

  TokenIdentifier

proc identifierType(scanner: var Scanner): TokenType =
  case scanner.start[]
  of 'a':
    return checkKeyword(scanner, 1, 2, "nd", TokenAnd)
  of 'c':
    return checkKeyword(scanner, 1, 4, "lass", TokenClass)
  of 'e':
    return checkKeyword(scanner, 1, 3, "lse", TokenElse)
  of 'f':
    if scanner.current - scanner.start > 1:
      case scanner.start[1]
      of 'a':
        return checkKeyword(scanner, 2, 3, "lse", TokenFalse)
      of 'o':
        return checkKeyword(scanner, 2, 1, "r", TokenFor)
      of 'u':
        return checkKeyword(scanner, 2, 1, "n", TokenFun)
      else:
        discard
  of 'i':
    return checkKeyword(scanner, 1, 1, "f", TokenIf)
  of 'n':
    return checkKeyword(scanner, 1, 2, "il", TokenNil)
  of 'o':
    return checkKeyword(scanner, 1, 1, "r", TokenOr)
  of 'p':
    return checkKeyword(scanner, 1, 4, "rint", TokenPrint)
  of 'r':
    return checkKeyword(scanner, 1, 5, "eturn", TokenReturn)
  of 's':
    return checkKeyword(scanner, 1, 4, "uper", TokenSuper)
  of 't':
    if scanner.current - scanner.start > 1:
      case scanner.start[1]
      of 'h':
        return checkKeyword(scanner, 2, 2, "is", TokenThis)
      of 'r':
        return checkKeyword(scanner, 2, 2, "ue", TokenTrue)
      else:
        discard
  of 'v':
    return checkKeyword(scanner, 1, 2, "ar", TokenVar)
  of 'w':
    return checkKeyword(scanner, 1, 4, "hile", TokenWhile)
  else:
    discard

  TokenIdentifier

proc identifier(scanner: var Scanner): Token =
  while isAlpha(peek(scanner)) or isDigit(peek(scanner)):
    discard advance(scanner)

  makeToken(scanner, identifierType(scanner))

proc number(scanner: var Scanner): Token =
  while isDigit(peek(scanner)):
    discard advance(scanner)

  if peek(scanner) == '.' and isDigit(peekNext(scanner)):
    discard advance(scanner)

    while isDigit(peek(scanner)):
      discard advance(scanner)

  makeToken(scanner, TokenNumber)

proc string(scanner: var Scanner): Token =
  while peek(scanner) != '"' and not(isAtEnd(scanner)):
    if peek(scanner) == '\n':
      scanner.line += 1

    discard advance(scanner)

  if isAtEnd(scanner):
    return errorToken(scanner, "Unterminated string.")

  discard advance(scanner)

  makeToken(scanner, TokenString)

proc scanToken*(scanner: var Scanner): Token =
  skipWhitespace(scanner)

  scanner.start = scanner.current

  if isAtEnd(scanner):
    return makeToken(scanner, TokenEof)

  let c = advance(scanner)

  if isAlpha(c):
    return identifier(scanner)

  if isDigit(c):
    return number(scanner)

  case c
  of '(':
    return makeToken(scanner, TokenLeftParen)
  of ')':
    return makeToken(scanner, TokenRightParen)
  of '{':
    return makeToken(scanner, TokenLeftBrace)
  of '}':
    return makeToken(scanner, TokenRightBrace)
  of ';':
    return makeToken(scanner, TokenSemicolon)
  of ',':
    return makeToken(scanner, TokenComma)
  of '.':
    return makeToken(scanner, TokenDot)
  of '-':
    return makeToken(scanner, TokenMinus)
  of '+':
    return makeToken(scanner, TokenPlus)
  of '/':
    return makeToken(scanner, TokenSlash)
  of '*':
    return makeToken(scanner, TokenStar)
  of '!':
    return makeToken(scanner, if match(scanner, '='): TokenBangEqual else: TokenBang)
  of '=':
    return makeToken(scanner, if match(scanner, '='): TokenEqualEqual else: TokenEqual)
  of '<':
    return makeToken(scanner, if match(scanner, '='): TokenLessEqual else: TokenLess)
  of '>':
    return makeToken(scanner, if match(scanner, '='): TokenGreaterEqual else: TokenGreater)
  of '"':
    return string(scanner)
  else:
    discard

  return errorToken(scanner, "Unexpected character.")
