import ./common

const
  FRAMES_MAX* = 64
  STACK_MAX = (FRAMES_MAX * UINT8_COUNT)

type
  # object.nim
  ObjType* = enum
    OBJT_BOUND_METHOD,
    OBJT_CLASS,
    OBJT_CLOSURE,
    OBJT_FUNCTION,
    OBJT_INSTANCE,
    OBJT_NATIVE,
    OBJT_STRING,
    OBJT_UPVALUE

  Obj* = object
    `type`*: ObjType
    isMarked*: bool
    next*: ptr Obj

  # end

  # value.nim

  ValueType* = enum
    VAL_BOOL,
    VAL_NIL,
    VAL_NUMBER,
    VAL_OBJ

when NAN_BOXING:
  type
    Value* = uint64
else:
  type
    Value* = object
      case `type`*: ValueType
      of VAL_BOOL:
        boolean*: bool
      of VAL_NIL, VAL_NUMBER:
        number*: float
      of VAL_OBJ:
        obj*: ptr Obj

type
  ValueArray* = object
    capacity*: int32
    count*: int32
    values*: ptr Value

  # end

type
  # chunk.nim

  OpCode* {.size: 1.} = enum
    OP_CONSTANT,
    OP_NIL,
    OP_TRUE,
    OP_FALSE,
    OP_POP,
    OP_GET_LOCAL,
    OP_SET_LOCAL,
    OP_GET_GLOBAL,
    OP_DEFINE_GLOBAL,
    OP_SET_GLOBAL,
    OP_GET_UPVALUE,
    OP_SET_UPVALUE,
    OP_GET_PROPERTY,
    OP_SET_PROPERTY,
    OP_GET_SUPER,
    OP_EQUAL,
    OP_GREATER,
    OP_LESS,
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,
    OP_NOT,
    OP_NEGATE,
    OP_PRINT,
    OP_JUMP,
    OP_JUMP_IF_FALSE,
    OP_LOOP,
    OP_CALL,
    OP_INVOKE,
    OP_SUPER_INVOKE,
    OP_CLOSURE,
    OP_CLOSE_UPVALUE,
    OP_RETURN,
    OP_CLASS,
    OP_INHERIT,
    OP_METHOD

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

  ParseFn* = proc(canAssign: bool) {.nimcall.}

  ParseRule* = object
    prefix*: ParseFn
    infix*: ParseFn
    precedence*: Precedence

  Local* = object
    name*: Token
    depth*: int32
    isCaptured*: bool

  Upvalue* = object
    index*: uint8
    isLocal*: bool

  FunctionType* = enum
    TYPE_FUNCTION,
    TYPE_INITIALIZER,
    TYPE_METHOD,
    TYPE_SCRIPT

  Compiler* = object
    enclosing*: ptr Compiler
    function*: ptr ObjFunction
    `type`*: FunctionType
    locals*: array[UINT8_COUNT, Local]
    localCount*: int32
    upvalues*: array[UINT8_COUNT, Upvalue]
    scopeDepth*: int32

  ClassCompiler* = object
    enclosing*: ptr ClassCompiler
    hasSuperclass*: bool

  # end

  # object.nim

  ObjFunction* = object
    obj*: Obj
    arity*: int32
    upvalueCount*: int32
    chunk*: Chunk
    name*: ptr ObjString

  NativeFn* = proc(argCount: int32, args: ptr Value): Value {.nimcall.}

  ObjNative* = object
    obj*: Obj
    function*: NativeFn

  ObjString* = object
    obj*: Obj
    length*: int32
    chars*: ptr char
    hash*: uint32

  ObjUpvalue* = object
    obj*: Obj
    location*: ptr Value
    closed*: Value
    next*: ptr ObjUpvalue

  ObjClosure* = object
    obj*: Obj
    function*: ptr ObjFunction
    upvalues*: ptr ptr ObjUpvalue
    upvalueCount*: int32

  ObjClass* = object
    obj*: Obj
    name*: ptr ObjString
    methods*: Table

  ObjInstance* = object
    obj*: Obj
    klass*: ptr ObjClass
    fields*: Table

  ObjBoundMethod* = object
    obj*: Obj
    receiver*: Value
    `method`*: ptr ObjClosure

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

  # vm.nim

  CallFrame* = object
    closure*: ptr ObjClosure
    ip*: ptr uint8
    slots*: ptr Value

  VM* = object
    frames*: array[FRAMES_MAX, CallFrame]
    frameCount*: int32

    stack*: array[STACK_MAX, Value]
    stackTop*: ptr Value
    globals*: Table
    strings*: Table
    initString*: ptr ObjString
    openUpvalues*: ptr ObjUpvalue

    bytesAllocated*: int # uint
    nextGC*: int # uint
    objects*: ptr Obj
    grayCount*: int32
    grayCapacity*: int32
    grayStack*: ptr ptr Obj

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
