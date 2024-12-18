import xxhash
import nint128

import
  std/[files, dirs, appdirs, sets, paths, syncio, strformat, logging, base64, strutils]

type Cache* = object
  hashes: HashSet[string]
  path: string

proc new_cache*(name: string): Cache =
  result.path =
    string (get_data_dir() / "podcaster".Path / name.Path).change_file_ext "txt"
  log(lvl_debug, &"new cache at {result.path}")
  if file_exists result.path.Path:
    for l in lines result.path:
      result.hashes.incl l
  else:
    create_dir result.path.Path.split_path.head

func hash*(cache: Cache, id: string): string =
  id.XXH3_128bits.to_bytes_b_e.encode(safe = true).strip(leading = false, chars = {'='})

proc incl*(c: var Cache, h: string) =
  if h notin c.hashes:
    let f = c.path.open fm_append
    f.write_line h
    f.close
    c.hashes.incl h

proc `notin`*(h: string, c: Cache): bool =
  h notin c.hashes
