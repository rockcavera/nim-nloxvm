import std/strformat

import ./object_helpers, ./types, ./value_helpers

# object.nim

proc printFunction(function: ptr ObjFunction) =
  if isNil(function.name):
    write(stdout, "<script>")
    return

  write(stdout, fmt"<fn {cast[cstring](function.name.chars)}>")

proc printObject(value: Value) =
  case objType(value)
  of OBJT_BOUND_METHOD:
    printFunction(asBoundMethod(value).`method`.function)
  of OBJT_CLASS:
    write(stdout, cast[cstring](asClass(value).name.chars))
  of OBJT_CLOSURE:
    printFunction(asClosure(value).function)
  of OBJT_FUNCTION:
    printFunction(asFunction(value))
  of OBJT_INSTANCE:
    write(stdout, fmt"{cast[cstring](asInstance(value).klass.name.chars)} instance")
  of OBJT_NATIVE:
    write(stdout, "<native fn>")
  of OBJT_STRING:
    write(stdout, cast[cstring](asCString(value)))
  of OBJT_UPVALUE:
    write(stdout, "upvalue")

# end

# value.nim

proc printValue*(value: Value) {.exportc.} =
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
