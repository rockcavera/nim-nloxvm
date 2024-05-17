import ./common

const
  framesMax* = 64
  stackMax = (framesMax * uint8Count)

type
  # object.nim
  ObjType* = enum
    ObjtBoundMethod
    ObjtClass
    ObjtClosure
    ObjtFunction
    ObjtInstance
    ObjtNative
    ObjtString
    ObjtUpvalue

  Obj* = object
    `type`*: ObjType
    isMarked*: bool
    next*: ptr Obj

  # end

  # value.nim

  ValueType* = enum
    ValBool
    ValNil
    ValNumber
    ValObj

when nanBoxing:
  type
    Value* = uint64
else:
  type
    Value* = object
      case `type`*: ValueType
      of ValBool:
        boolean*: bool
      of ValNil, ValNumber:
        number*: float
      of ValObj:
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
    OpConstant
    OpNil
    OpTrue
    OpFalse
    OpPop
    OpGetLocal
    OpSetLocal
    OpGetGlobal
    OpDefineGlobal
    OpSetGlobal
    OpGetUpvalue
    OpSetUpvalue
    OpGetProperty
    OpSetProperty
    OpGetSuper
    OpEqual
    OpGreater
    OpLess
    OpAdd
    OpSubtract
    OpMultiply
    OpDivide
    OpNot
    OpNegate
    OpPrint
    OpJump
    OpJumpIfFalse
    OpLoop
    OpCall
    OpInvoke
    OpSuperInvoke
    OpClosure
    OpCloseUpvalue
    OpReturn
    OpClass
    OpInherit
    OpMethod

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
    PrecNone
    PrecAssignment  # =
    PrecOr          # or
    PrecAnd         # and
    PrecEquality    # == !=
    PrecComparison  # < > <= >=
    PrecTerm        # + -
    PrecFactor      # * /
    PrecUnary       # ! -
    PrecCall        # . ()
    PrecPrimary

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
    TypeFunction
    TypeInitializer
    TypeMethod
    TypeScript

  Compiler* = object
    enclosing*: ptr Compiler
    function*: ptr ObjFunction
    `type`*: FunctionType
    locals*: array[uint8Count, Local]
    localCount*: int32
    upvalues*: array[uint8Count, Upvalue]
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
    TokenLeftParen
    TokenRightParen
    TokenLeftBrace
    TokenRightBrace
    TokenComma
    TokenDot
    TokenMinus
    TokenPlus
    TokenSemicolon
    TokenSlash
    TokenStar
    # One or two character tokens.
    TokenBang
    TokenBangEqual
    TokenEqual
    TokenEqualEqual
    TokenGreater
    TokenGreaterEqual
    TokenLess
    TokenLessEqual
    # Literals.
    TokenIdentifier
    TokenString
    TokenNumber
    # Keywords.
    TokenAnd
    TokenClass
    TokenElse
    TokenFalse
    TokenFor
    TokenFun
    TokenIf
    TokenNil
    TokenOr
    TokenPrint
    TokenReturn
    TokenSuper
    TokenThis
    TokenTrue
    TokenVar
    TokenWhile

    TokenError
    TokenEof

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
    frames*: array[framesMax, CallFrame]
    frameCount*: int32

    stack*: array[stackMax, Value]
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
    InterpretOk
    InterpretCompileError
    InterpretRuntimeError

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
