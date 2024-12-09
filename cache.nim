import xxhash
import nint128

import std/os
import std/sets
import std/json
import std/paths
import std/times
import std/base64
import std/syncio
import std/strutils

import ytdlp

type Cache* = tuple[hashes: HashSet[string], file: File]

proc new_cache*(path: Path): Cache =
  if file_exists path.string:
    result.hashes = to_hash_set split_lines read_file path.string
  result.file = path.string.open fm_write

proc incl*(c: var Cache, m: Media) =
  let id =
    %*{"uploader": m.uploader, "title": m.title, "uploaded": to_unix to_time m.uploaded}
  let h = ($id).XXH3_128bits.to_bytes_b_e.encode.replace("=", "")
  if h notin c.hashes:
    c.file.write_line h
    c.hashes.incl h
