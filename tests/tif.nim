{.used.}
import std/private/[ospaths2], std/unittest

import ./tconfig

const folder = "if"

suite "If":
  test "Dangling else":
    const
      script = folder / "dangling_else.lox"
      expectedExitCode = 0
      expectedOutput = """good
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Else":
    const
      script = folder / "else.lox"
      expectedExitCode = 0
      expectedOutput = """good
good
block
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "If":
    const
      script = folder / "if.lox"
      expectedExitCode = 0
      expectedOutput = """good
block
true
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Truth":
    const
      script = folder / "truth.lox"
      expectedExitCode = 0
      expectedOutput = """false
nil
true
0
empty
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Var in else":
    const
      script = folder / "var_in_else.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'var': Expect expression.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Var in then":
    const
      script = folder / "var_in_then.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'var': Expect expression.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Fun in else":
    const
      script = folder / "fun_in_else.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'fun': Expect expression.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Fun in then":
    const
      script = folder / "fun_in_then.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'fun': Expect expression.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Class in else":
    const
      script = folder / "class_in_else.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'class': Expect expression.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Class in then":
    const
      script = folder / "class_in_then.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'class': Expect expression.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)
