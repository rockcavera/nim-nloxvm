{.used.}
import std/private/[ospaths2], std/unittest

import ./tconfig

const folder = "call"

suite "Call":
  test "Bool":
    const
      script = folder / "bool.lox"
      expectedExitCode = 70
      expectedOutput = """Can only call functions and classes.
[line 1] in script
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Nil":
    const
      script = folder / "nil.lox"
      expectedExitCode = 70
      expectedOutput = """Can only call functions and classes.
[line 1] in script
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Num":
    const
      script = folder / "num.lox"
      expectedExitCode = 70
      expectedOutput = """Can only call functions and classes.
[line 1] in script
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "String":
    const
      script = folder / "string.lox"
      expectedExitCode = 70
      expectedOutput = """Can only call functions and classes.
[line 1] in script
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Object":
    const
      script = folder / "object.lox"
      expectedExitCode = 70
      expectedOutput = """Can only call functions and classes.
[line 4] in script
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)
