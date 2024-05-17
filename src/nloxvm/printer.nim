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
  of ObjtBoundMethod:
    printFunction(asBoundMethod(value).`method`.function)
  of ObjtClass:
    let klass = asClass(value)

    discard writeBuffer(stdout, klass.name.chars, klass.name.length)
  of ObjtClosure:
    printFunction(asClosure(value).function)
  of ObjtFunction:
    printFunction(asFunction(value))
  of ObjtInstance:
    let instance = asInstance(value)

    discard writeBuffer(stdout, instance.klass.name.chars, instance.klass.name.length)

    write(stdout, " instance")
  of ObjtNative:
    write(stdout, "<native fn>")
  of ObjtString:
    let string = asString(value)

    discard writeBuffer(stdout, string.chars, string.length)
  of ObjtUpvalue:
    write(stdout, "upvalue")

# end

# value.nim

proc printValue*(value: Value) =
  when nanBoxing:
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
    of ValBool:
      write(stdout, $asBool(value))
    of ValNil:
      write(stdout, "nil")
    of ValNumber:
      write(stdout, fmt"{asNumber(value):g}")
    of ValObj:
      printObject(value)

# end
