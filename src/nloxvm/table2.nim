import ./types, ./value_helpers

import ./private/pointer_arithmetics

# table.nim

proc findEntry*(entries: ptr Entry, capacity: int32, key: ptr ObjString): ptr Entry =
  var
    index = key.hash and uint32(capacity - 1)
    tombstone = cast[ptr Entry](nil)

  while true:
    let entry = entries + index

    if isNil(entry.key):
      if isNil(entry.value):
        return if not isNil(tombstone): tombstone else: entry
      else:
        if isNil(tombstone):
          tombstone = entry
    elif entry.key == key:
      return entry

    index = (index + 1) and uint32(capacity - 1)

proc tableDelete*(table: var Table, key: ptr ObjString): bool =
  if table.count == 0:
    return false

  var entry = findEntry(table.entries, table.capacity, key)

  if isNil(entry.key):
    return false

  entry.key = nil
  entry.value = boolVal(true)

  true

# end
