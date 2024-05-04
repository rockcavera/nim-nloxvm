import ./memory, ./types, ./value_helpers

import ./private/pointer_arithmetics

const TABLE_MAX_LOAD = 0.75'f32

proc initTable*(table: var Table) =
  table.count = 0
  table.capacity = 0
  table.entries = nil

proc freeTable*(table: var Table) =
  free_array(Entry, table.entries, table.capacity)
  initTable(table)

proc findEntry(entries: ptr Entry, capacity: int32, key: ptr ObjString): ptr Entry =
  var
    index = key.hash mod uint32(capacity)
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

    index = (index + 1) mod uint32(capacity)

proc tableGet*(table: var Table, key: ptr ObjString, value: var Value): bool =
  if table.count == 0:
    return false

  let entry = findEntry(table.entries, table.capacity, key)

  if isNil(entry.key):
    return false

  value = entry.value

  true

proc adjustCapacity(table: var Table, capacity: int32) =
  let entries = allocate(Entry, capacity)

  for i in 0 ..< capacity:
    entries[i].key = nil
    entries[i].value = nilVal()

  table.count = 0

  for i in 0 ..< table.capacity:
    let entry = table.entries + i

    if isNil(entry.key):
      continue

    var dest = findEntry(entries, capacity, entry.key)

    dest.key = entry.key
    dest.value = entry.value

    inc(table.count)

  free_array(Entry, table.entries, table.capacity)

  table.entries = entries
  table.capacity = capacity

proc tableSet*(table: var Table, key: ptr ObjString, value: Value): bool =
  if float32(table.count + 1) > (float32(table.capacity) * TABLE_MAX_LOAD):
    let capacity = grow_capacity(table.capacity)

    adjustCapacity(table, capacity)

  var entry = findEntry(table.entries, table.capacity, key)

  result = isNil(entry.key)

  if result and isNil(entry.value):
    inc(table.count)

  entry.key = key
  entry.value = value

proc tableDelete*(table: var Table, key: ptr ObjString): bool =
  if table.count == 0:
    return false

  var entry = findEntry(table.entries, table.capacity, key)

  if isNil(entry.key):
    return false

  entry.key = nil
  entry.value = boolVal(true)

  true

proc tableAddAll*(`from`: var Table, to: var Table) =
  for i in 0 ..< `from`.capacity:
    let entry = `from`.entries + i

    if not isNil(entry.key):
      discard tableSet(to, entry.key, entry.value)

proc tableFindString*(table: var Table, chars: ptr char, length: int32, hash: uint32): ptr ObjString =
  if table.count == 0:
    return nil

  var index = hash mod uint32(table.capacity)

  while true:
    let entry = table.entries + index

    if isNil(entry.key):
      if isNil(entry.value):
        return nil
    elif entry.key.length == length and entry.key.hash == hash and cmpMem(entry.key.chars, chars, length) == 0:
      return entry.key

    index = (index + 1) mod uint32(table.capacity)

proc tableRemoveWhite*(table: var Table) =
  for i in 0 ..< table.capacity:
    let entry = addr table.entries[i]

    if not(isNil(entry.key)) and not(entry.key.obj.isMarked):
      discard tableDelete(table, entry.key)
