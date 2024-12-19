import std/[files, dirs, appdirs, sets, paths, syncio, strformat, logging, json]

type Cache* = object
  items: HashSet[JsonNode]
  path: string

proc new_cache*(name: string): Cache =
  result.path =
    string (get_data_dir() / "podcaster".Path / name.Path).change_file_ext "txt"
  log(lvl_debug, &"new cache at {result.path}")
  if file_exists result.path.Path:
    for l in lines result.path:
      result.items.incl parse_json l
  else:
    create_dir result.path.Path.split_path.head

proc incl*(cache: var Cache, item: JsonNode) =
  if item notin cache.items:
    cache.items.incl item
    let f = cache.path.open fm_append
    f.write_line $item
    f.close

proc `notin`*(item: JsonNode, cache: Cache): bool =
  item notin cache.items
