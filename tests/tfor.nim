{.used.}
import std/private/[ospaths2], std/unittest

import ./tconfig

const folder = "for"

suite "For":
  test "Scope":
    const
      script = folder / "scope.lox"
      expectedExitCode = 0
      expectedOutput = """0
-1
after
0
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Statement condition":
    const
      script = folder / "statement_condition.lox"
      expectedExitCode = 65
      expectedOutput = """[line 3] Error at '{': Expect expression.
[line 3] Error at ')': Expect ';' after expression.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Statement increment":
    const
      script = folder / "statement_increment.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2] Error at '{': Expect expression.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Statement initializer":
    const
      script = folder / "statement_initializer.lox"
      expectedExitCode = 65
      expectedOutput = """[line 3] Error at '{': Expect expression.
[line 3] Error at ')': Expect ';' after expression.
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

  test "Return inside":
    const
      script = folder / "return_inside.lox"
      expectedExitCode = 0
      expectedOutput = """i
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

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
done
0
1
0
1
2
0
1
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Closure in body":
    const
      script = folder / "closure_in_body.lox"
      expectedExitCode = 0
      expectedOutput = """4
1
4
2
4
3
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Return closure":
    const
      script = folder / "return_closure.lox"
      expectedExitCode = 0
      expectedOutput = """i
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)
