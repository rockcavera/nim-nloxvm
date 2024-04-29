{.used.}
import std/private/[ospaths2], std/unittest

import ./tconfig

const folder = "variable"

suite "Variable":
  test "Redeclare global":
    const
      script = folder / "redeclare_global.lox"
      expectedExitCode = 0
      expectedOutput = """nil
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Redefine global":
    const
      script = folder / "redefine_global.lox"
      expectedExitCode = 0
      expectedOutput = """2
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Undefined global":
    const
      script = folder / "undefined_global.lox"
      expectedExitCode = 70
      expectedOutput = """Undefined variable 'notDefined'.
[line 1] in script
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Uninitialized":
    const
      script = folder / "uninitialized.lox"
      expectedExitCode = 0
      expectedOutput = """nil
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Use false as var":
    const
      script = folder / "use_false_as_var.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'false': Expect variable name.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Use global in initializer":
    const
      script = folder / "use_global_in_initializer.lox"
      expectedExitCode = 0
      expectedOutput = """value
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Use nil as var":
    const
      script = folder / "use_nil_as_var.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'nil': Expect variable name.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Use this as var":
    const
      script = folder / "use_this_as_var.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'this': Expect variable name.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)
