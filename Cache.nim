import std/files
import std/uri
import std/dirs
import std/appdirs
import std/sets
import std/paths
import std/syncio
import std/strformat
import std/logging
import std/strutils

import ytdlp

type Cache* = tuple[hashes: HashSet[string], path: Path]

proc new_cache*(uri: Uri): Cache =
  result.path =
    (get_data_dir() / "podcaster".Path / uri.hostname.Path).change_file_ext "txt"
  log(lvl_debug, &"new cache at {result.path.string}")
  if file_exists result.path:
    result.hashes = to_hash_set split_lines read_file result.path.string

proc incl(c: var Cache, h: string) =
  if h notin c.hashes:
    create_dir c.path.split_path.head
    let f = c.path.string.open fm_append
    f.write_line h
    f.close
    c.hashes.incl h

proc incl*(c: var Cache, m: Media) =
  c.incl m.hash

proc incl*(c: var Cache, p: Playlist) =
  c.incl p.hash

proc incl*(c: var Cache, u: Uri) =
  c.incl u.safe_hash

proc `notin`*(m: Media, c: Cache): bool =
  m.hash notin c.hashes

proc `in`*(u: Uri, c: Cache): bool =
  u.safe_hash in c.hashes

proc `notin`*(u: Uri, c: Cache): bool =
  u.safe_hash notin c.hashes
