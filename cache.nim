import xxhash
import nint128

import std/files
import std/base64
import std/uri
import std/appdirs
import std/sets
import std/paths
import std/syncio
import std/strutils

import ytdlp

type Cache* = tuple[hashes: HashSet[string], path: Path]

proc new_cache*(uri: Uri): Cache =
  result.path = (get_data_dir() / uri.hostname.Path).add_file_ext "txt"
  if file_exists result.path:
    result.hashes = to_hash_set split_lines read_file result.path.string

func hash(u: Uri): string =
  return ($u).XXH3_128bits.to_bytes_b_e.encode(safe = true).replace("=", "")

proc incl(c: var Cache, h: string) =
  if h notin c.hashes:
    let f = c.path.string.open fm_append
    f.write_line h
    f.close
    c.hashes.incl h

proc incl*(c: var Cache, m: Media) =
  c.incl m.hash

proc incl*(c: var Cache, p: Playlist) =
  c.incl p.hash

proc incl*(c: var Cache, u: Uri) =
  c.incl u.hash

proc `notin`*(m: Media, c: Cache): bool =
  m.hash notin c.hashes

proc `in`*(u: Uri, c: Cache): bool =
  u.hash in c.hashes

proc `notin`*(u: Uri, c: Cache): bool =
  u.hash notin c.hashes
