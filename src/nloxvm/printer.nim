import std/strformat

import ./object, ./types, ./value

# value.nim

proc printValue*(value: Value) =
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
