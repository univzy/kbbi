type LRUCache* = object
  entries*: seq[(cstring, cstring)]
  maxSize*: int

proc newLRUCache*(maxSize: int): LRUCache =
  LRUCache(entries: @[], maxSize: maxSize)

proc lruGet*(cache: var LRUCache, key: cstring): cstring =
  for i in 0 ..< cache.entries.len:
    if cache.entries[i][0] == key:
      let val = cache.entries[i][1]
      cache.entries.delete(i)
      cache.entries.insert((key, val), 0)
      return val
  return ""

proc lruSet*(cache: var LRUCache, key: cstring, value: cstring) =
  for i in 0 ..< cache.entries.len:
    if cache.entries[i][0] == key:
      cache.entries.delete(i)
      cache.entries.insert((key, value), 0)
      return
  if cache.entries.len >= cache.maxSize:
    cache.entries.setLen(cache.maxSize - 1)
  cache.entries.insert((key, value), 0)
