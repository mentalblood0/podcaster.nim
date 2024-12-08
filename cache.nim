import xxhash
import nint128

import std/os
import std/sets
import std/json
import std/times
import std/sugar
import std/base64
import std/syncio
import std/strutils

import ytdlp

type Cache* = tuple[hashes: HashSet[string], file: File]

proc new_cache*(path: string): Cache =
  if file_exists path:
    result.hashes = to_hash_set split_lines read_file path
  result.file = path.open fm_write

proc incl*(c: var Cache, m: Media) =
  let id =
    %*{"uploader": m.uploader, "title": m.title, "uploaded": to_unix to_time m.uploaded}
  let h = (encode to_bytes_b_e XXH3_128bits $id).replace("=", "")
  if h notin c.hashes:
    c.file.write_line h
    c.hashes.incl h
