import std/[sets, syncio, json, strformat, logging, os]

let cache_dir* = get_data_dir() / "podcaster"

type Cache* = object
  items: HashSet[JsonNode]
  path: string

proc new_cache*(name: string): Cache =
  result.path = cache_dir / name & ".txt"
  lvl_info.log &"store uploaded items identifiers at {result.path}"
  if file_exists result.path:
    for l in lines result.path:
      result.items.incl parse_json l
  else:
    create_dir cache_dir

proc incl*(cache: var Cache, item: JsonNode) =
  if item notin cache.items:
    cache.items.incl item
    let f = cache.path.open fm_append
    f.write_line $item
    f.close

func `in`*(item: JsonNode, cache: Cache): bool =
  item in cache.items

template `notin`*(item: JsonNode, cache: Cache): bool =
  not (item in cache)
