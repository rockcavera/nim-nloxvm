{.used.}
import std/private/[ospaths2], std/unittest

import ./tconfig

const folder = "limit"

suite "Limit":
  test "Loop too large":
    const
      script = folder / "loop_too_large.lox"
      expectedExitCode = 65
      expectedOutput = """[line 2351] Error at '}': Loop body too large.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "No reuse constants":
    const
      script = folder / "no_reuse_constants.lox"
      expectedExitCode = 65
      expectedOutput = """[line 35] Error at '1': Too many constants in one chunk.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Stack overflow":
    const
      script = folder / "stack_overflow.lox"
      expectedExitCode = 70
      expectedOutput = """Stack overflow.
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 18] in foo()
[line 21] in script
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Too many constants":
    const
      script = folder / "too_many_constants.lox"
      expectedExitCode = 65
      expectedOutput = """[line 35] Error at '"oops"': Too many constants in one chunk.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Too many locals":
    const
      script = folder / "too_many_locals.lox"
      expectedExitCode = 65
      expectedOutput = """[line 52] Error at 'oops': Too many local variables in function.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Too many upvalues":
    const
      script = folder / "too_many_upvalues.lox"
      expectedExitCode = 65
      expectedOutput = """[line 102] Error at 'oops': Too many closure variables in function.
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)
