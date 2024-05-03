{.used.}
import std/private/[ospaths2], std/unittest

import ./tconfig

const folder = "function"

suite "Function":
  test "Body must be block":
    const
      script = folder / "body_must_be_block.lox"
      expectedExitCode = 65
      expectedOutput = """[line 3] Error at '123': Expect '{' before function body.
[line 4] Error at end: Expect '}' after block.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Empty body":
    const
      script = folder / "empty_body.lox"
      expectedExitCode = 0
      expectedOutput = """nil
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Extra arguments":
    const
      script = folder / "extra_arguments.lox"
      expectedExitCode = 70
      expectedOutput = """Expected 2 arguments but got 4.
[line 6] in script
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Missing arguments":
    const
      script = folder / "missing_arguments.lox"
      expectedExitCode = 70
      expectedOutput = """Expected 2 arguments but got 1.
[line 3] in script
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Missing comma in parameters":
    const
      script = folder / "missing_comma_in_parameters.lox"
      expectedExitCode = 65
      expectedOutput = """[line 3] Error at 'c': Expect ')' after parameters.
[line 4] Error at end: Expect '}' after block.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Mutual recursion":
    const
      script = folder / "mutual_recursion.lox"
      expectedExitCode = 0
      expectedOutput = """true
true
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Nested call with arguments":
    const
      script = folder / "nested_call_with_arguments.lox"
      expectedExitCode = 0
      expectedOutput = """hello world
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Parameters":
    const
      script = folder / "parameters.lox"
      expectedExitCode = 0
      expectedOutput = """0
1
3
6
10
15
21
28
36
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Print":
    const
      script = folder / "print.lox"
      expectedExitCode = 0
      expectedOutput = """<fn foo>
<native fn>
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Recursion":
    const
      script = folder / "recursion.lox"
      expectedExitCode = 0
      expectedOutput = """21
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Too many arguments":
    const
      script = folder / "too_many_arguments.lox"
      expectedExitCode = 65
      expectedOutput = """[line 260] Error at 'a': Can't have more than 255 arguments.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Too many parameters":
    const
      script = folder / "too_many_parameters.lox"
      expectedExitCode = 65
      expectedOutput = """[line 257] Error at 'a': Can't have more than 255 parameters.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Local mutual recursion":
    const
      script = folder / "local_mutual_recursion.lox"
      expectedExitCode = 70
      expectedOutput = """Undefined variable 'isOdd'.
[line 4] in isEven()
[line 12] in script
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Local recursion":
    const
      script = folder / "local_recursion.lox"
      expectedExitCode = 0
      expectedOutput = """21
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)
