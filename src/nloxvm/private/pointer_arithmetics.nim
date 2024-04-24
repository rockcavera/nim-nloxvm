template `+`*[T](p: ptr T, x: SomeInteger): ptr T =
  let offset = uint(sizeof(T)) * uint(x)

  cast[ptr T](cast[uint](p) + offset)

template `+=`*[T](p: ptr T, x: SomeInteger) =
  p = p + x

template inc*[T](p: ptr T, x: SomeInteger = 1) =
  p = p + x

template `-`*[T](p: ptr T, x: SomeInteger): ptr T =
  let offset = uint(sizeof(T)) * uint(x)

  cast[ptr T](cast[uint](p) - offset)

template `-=`*[T](p: ptr T, x: SomeInteger) =
  p = p - x

template dec*[T](p: ptr T, x: SomeInteger = 1) =
  p = p - x

template `+`*(p: pointer, x: SomeInteger): pointer =
  cast[pointer](cast[uint](p) + uint(x))

template `+=`*(p: pointer, x: SomeInteger) =
  p = p + x

template inc*(p: pointer, x: SomeInteger = 1) =
  p = p + x

template `-`*(p: pointer, x: SomeInteger): pointer =
  cast[pointer](cast[uint](p) - uint(x))

template `-=`*(p: pointer, x: SomeInteger) =
  p = p - x

template dec*(p: pointer, x: SomeInteger = 1) =
  p = p - x

template `-`*[T](a, b: ptr T): int =
  cast[int]((cast[uint](a) - cast[uint](b)) div uint(sizeof(T)))

template `-`*(a, b: pointer): int =
  cast[int](cast[uint](a) - cast[uint](b))
