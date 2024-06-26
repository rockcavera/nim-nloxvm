{.used.}
import std/private/[ospaths2], std/unittest

import ./tconfig

const folder = "block"

suite "Block":
  test "Scope":
    const
      script = folder / "scope.lox"
      expectedExitCode = 0
      expectedOutput = """inner
outer
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)

  test "Empty":
    const
      script = folder / "empty.lox"
      expectedExitCode = 0
      expectedOutput = """ok
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)
