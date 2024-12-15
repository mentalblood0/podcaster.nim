# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import
  std/
    [files, uri, dirs, appdirs, sets, paths, syncio, strformat, logging, strutils, nre]

import ytdlp

type Cache* = tuple[hashes: HashSet[string], path: Path]

proc cache_file_name(url: Uri): string =
  block bandcamp:
    let m = ($url).match bandcamp_url_regex
    if is_some m:
      return m.get.captures[0]
  block youtube_channel:
    let m = ($url).match youtube_channel_url_regex
    if is_some m:
      return m.get.captures[0]
  block youtube_topic:
    let m = ($url).match youtube_topic_url_regex
    if is_some m:
      return m.get.captures[0]

proc new_cache*(url: Uri): Cache =
  result.path =
    (get_data_dir() / "podcaster".Path / url.cache_file_name.Path).change_file_ext "txt"
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

proc incl*(c: var Cache, u: Uri) =
  c.incl u.safe_hash

proc `in`*(m: Media, c: Cache): bool =
  m.hash in c.hashes

proc `notin`*(m: Media, c: Cache): bool =
  m.hash notin c.hashes

proc `in`*(u: Uri, c: Cache): bool =
  u.safe_hash in c.hashes

proc `notin`*(u: Uri, c: Cache): bool =
  u.safe_hash notin c.hashes
