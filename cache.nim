import os
import xxhash
import std/sets
import std/syncio
import std/strutils

import ytdlp

type Cache* = tuple[hashes: HashSet[string], file: File]

proc new_cache*(path: string): Cache =
  if file_exists path:
    result.hashes = to_hash_set split_lines read_file path
  result.file = path.open fm_write

proc incl*(c: var Cache, m: Media) =
  let h = $XXH3_128bits $m.url
  if h notin c.hashes:
    c.file.write_line h
    c.hashes.incl h
