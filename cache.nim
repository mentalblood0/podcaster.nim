import
  std/[files, dirs, appdirs, sets, paths, syncio, json, logging, strformat, times, math]

type Cache* = object
  items: HashSet[JsonNode]
  path: string

proc new_cache*(name: string): Cache =
  result.path = (get_data_dir() / "podcaster".Path / name.Path).string & ".txt"
  if file_exists result.path.Path:
    let start = cpu_time()
    for l in lines result.path:
      result.items.incl parse_json l
    let finish = cpu_time()
    let duration = init_duration(nanoseconds = int ((finish - start) * 1000000000))
    lvl_debug.log &"loaded cache entries: {result.items.len} in {duration}"
  else:
    create_dir result.path.Path.split_path.head

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
