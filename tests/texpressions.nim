{.used.}
import std/private/[ospaths2], std/unittest

import ./tconfig

const folder = "expressions"

suite "Expressions":
  test "Evaluate":
    const
      script = folder / "evaluate.lox"
      expectedExitCode = 0
      expectedOutput = """2
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)
