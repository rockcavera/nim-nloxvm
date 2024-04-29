{.used.}
import std/private/[ospaths2], std/unittest

import ./tconfig

const folder = "while"

suite "While":
  test "Syntax":
    const
      script = folder / "syntax.lox"
      expectedExitCode = 0
      expectedOutput = """1
2
3
0
1
2
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Var in body":
    const
      script = folder / "var_in_body.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'var': Expect expression.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Fun in body":
    const
      script = folder / "fun_in_body.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'fun': Expect expression.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Class in body":
    const
      script = folder / "class_in_body.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at 'class': Expect expression.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)
