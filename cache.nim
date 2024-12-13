import std/files
import std/sets
import std/paths
import std/syncio
import std/strutils

import ytdlp

type Cache* = tuple[hashes: HashSet[string], file: File]

proc new_cache*(path: Path): Cache =
  if file_exists path:
    result.hashes = to_hash_set split_lines read_file path.string
  result.file = path.string.open fm_write

proc incl*(c: var Cache, m: Media) =
  let h = m.hash
  if h notin c.hashes:
    c.file.write_line h
    c.hashes.incl h
