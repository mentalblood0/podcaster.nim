# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import std/[options, strutils, sugar, sequtils, json, nre]

import cache

type
  Item* = object
    url*: string
    performer*: Option[string]
    title*: string
    duration*: int
    cache_items*: seq[JsonNode]
    thumbnail_id*: string
    keep_thumbnail*: bool
    need_proxy*: bool

  ItemsCollector*[T] = object
    url*: T
    cache*: Cache
    performer_from_title*: bool

  Downloaded* = object
    audio_path*: string
    thumbnail_path*: string

  UnsupportedUrlError* = object of ValueError

var ytdlp_proxy* = ""

proc decouple_performer_and_title*(
    performer: string, title: string
): tuple[performer: Option[string], title: string] =
  var p = performer.replace(re"Various Artists *(?:-|—)? *", "").strip
  var t = title.replace(re"Various Artists *(?:-|—)? *", "").strip

  if p in ["", "NA"]:
    let splitted = t.split(re"-|—", 1).map (s: string) => s.strip
    if splitted.len == 1:
      return (performer: none(string), title: t)
    else:
      p = splitted[0].strip
      t = splitted[1].strip

  return (performer: some(p), title: strip t.replace p & " -")
