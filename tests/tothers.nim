{.used.}
import std/unittest

import ./tconfig

suite "Others":
  test "Empty file":
    const
      script = "empty_file.lox"
      expectedExitCode = 0
      expectedOutput = """
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Precedence":
    const
      script = "precedence.lox"
      expectedExitCode = 0
      expectedOutput = """14
8
4
0
true
true
true
true
0
0
0
0
4
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Unexpected character":
    const
      script = "unexpected_character.lox"
      expectedExitCode = 65
      expectedOutput = """[line 3] Error: Unexpected character.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)
