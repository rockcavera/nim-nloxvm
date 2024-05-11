import std/strformat

import ./common, ./object_helpers, ./types, ./value_helpers

# object.nim

proc printFunction(function: ptr ObjFunction) =
  if isNil(function.name):
    write(stdout, "<script>")
    return

  write(stdout, "<fn ")

  discard writeBuffer(stdout, function.name.chars, function.name.length)

  write(stdout, ">")

proc printObject(value: Value) =
  case objType(value)
  of OBJT_BOUND_METHOD:
    printFunction(asBoundMethod(value).`method`.function)
  of OBJT_CLASS:
    let klass = asClass(value)

    discard writeBuffer(stdout, klass.name.chars, klass.name.length)
  of OBJT_CLOSURE:
    printFunction(asClosure(value).function)
  of OBJT_FUNCTION:
    printFunction(asFunction(value))
  of OBJT_INSTANCE:
    let instance = asInstance(value)

    discard writeBuffer(stdout, instance.klass.name.chars, instance.klass.name.length)

    write(stdout, " instance")
  of OBJT_NATIVE:
    write(stdout, "<native fn>")
  of OBJT_STRING:
    let string = asString(value)

    discard writeBuffer(stdout, string.chars, string.length)
  of OBJT_UPVALUE:
    write(stdout, "upvalue")

# end

# value.nim

proc printValue*(value: Value) =
  when NAN_BOXING:
    if isBool(value):
      write(stdout, $asBool(value))
    elif isNil(value):
      write(stdout, "nil")
    elif isNumber(value):
      write(stdout, fmt"{asNumber(value):g}")
    elif isObj(value):
      printObject(value)
  else:
    case value.`type`
    of VAL_BOOL:
      write(stdout, $asBool(value))
    of VAL_NIL:
      write(stdout, "nil")
    of VAL_NUMBER:
      write(stdout, fmt"{asNumber(value):g}")
    of VAL_OBJ:
      printObject(value)

# end
