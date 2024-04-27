const STACK_MAX = 256

type
  # chunk.nim

  OpCode* {.size: 1.} = enum
    OP_CONSTANT,
    OP_NIL,
    OP_TRUE,
    OP_FALSE,
    OP_EQUAL,
    OP_GREATER,
    OP_LESS,
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,
    OP_NOT,
    OP_NEGATE,
    OP_RETURN

  Chunk* = object
    count*: int32
    capacity*: int32
    code*: ptr uint8
    lines*: ptr int32
    constants*: ValueArray

  # end

  # compiler.nim

  Parser* = object
    current*: Token
    previous*: Token
    hadError*: bool
    panicMode*: bool

  Precedence* = enum
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

  ParseFn* = proc() {.nimcall.}

  ParseRule* = object
    prefix*: ParseFn
    infix*: ParseFn
    precedence*: Precedence

  # end

  # object.nim

  ObjType* = enum
    OBJT_STRING

  Obj* = object
    `type`*: ObjType
    next*: ptr Obj

  ObjString* = object
    obj*: Obj
    length*: int32
    chars*: ptr char
    hash*: uint32

  # end

  # scanner.nim

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

  Scanner* = object
    start*: ptr char
    current*: ptr char
    line*: int32

  # end

  # value.nim

  ValueType* = enum
    VAL_BOOL,
    VAL_NIL,
    VAL_NUMBER,
    VAL_OBJ

  Value* = object
    case `type`*: ValueType
    of VAL_BOOL:
      boolean*: bool
    of VAL_NIL, VAL_NUMBER:
      number*: float
    of VAL_OBJ:
      obj*: ptr Obj

  ValueArray* = object
    capacity*: int32
    count*: int32
    values*: ptr Value

  # end

  # vm.nim

  VM* = object
    chunk*: ptr Chunk
    ip*: ptr uint8
    stack*: array[STACK_MAX, Value]
    stackTop*: ptr Value
    strings*: Table
    objects*: ptr Obj

  InterpretResult* = enum
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR

  # end

  # table.nim

  Entry* = object
    key*: ptr ObjString
    value*: Value

  Table* = object
    count*: int32
    capacity*: int32
    entries*: ptr Entry

  # end
