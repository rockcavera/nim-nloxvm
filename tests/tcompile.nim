{.used.}
import std/unittest

disableParamFiltering()

import ./tconfig

suite "Compile":
  test "nloxvm interpreter":
    check true == nloxvmCompiled()
