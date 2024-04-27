import system/ansi_c

import ./globals, ./types

template allocate*[T](`type`: typedesc[T], count: untyped): ptr T =
  cast[ptr T](reallocate(nil, 0, sizeof(`type`) * count))

template free[T](`type`: typedesc, `pointer`: T) =
  discard reallocate(`pointer`, sizeof(`type`), 0)

template grow_capacity*[T](capacity: T): T =
  if capacity < 8: 8
  else: capacity * 2

template grow_array*[T](`type`: typedesc, `pointer`: T, oldCount, newCount: untyped): T =
  cast[T](reallocate(`pointer`, sizeof(`type`) * oldCount, sizeof(`type`) * newCount))

template free_array*[T](`type`: typedesc, `pointer`: T, oldCount: untyped) =
  discard reallocate(`pointer`, sizeof(`type`) * oldCount, 0)

proc reallocate*(`pointer`: pointer, oldSize: int, newSize: int): pointer =
  if newSize == 0:
    c_free(`pointer`)
    return nil

  result = c_realloc(`pointer`, newSize.csize_t)

  if isNil(result):
    quit(1)

proc freeObject(`object`: ptr Obj) =
  case `object`.`type`
  of OBJT_STRING:
    let string = cast[ptr ObjString](`object`)

    free_array(char, string.chars, string.length + 1)

    free(ObjString, `object`)

proc freeObjects*() =
  var `object` = vm.objects

  while `object` != nil:
    let next = `object`.next

    freeObject(`object`)

    `object` = next
