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
