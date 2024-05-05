{.used.}
import std/private/[ospaths2], std/unittest

import ./tconfig

const folder = "class"

suite "Class":
  test "empty":
    const
      script = folder / "empty.lox"
      expectedExitCode = 0
      expectedOutput = """Foo
"""

    check (expectedOutput, expectedExitCode) == nloxvmTest(script)
