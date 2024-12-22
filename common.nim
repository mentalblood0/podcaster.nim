import std/[options, strutils, sugar, sequtils, json]

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

  ItemsCollector*[T] = object
    url*: T
    cache*: Cache

  Downloaded* = object
    audio_path*: string
    thumbnail_path*: string

  UnsupportedUrlError* = object of ValueError

var ytdlp_proxy* = ""

func decouple_performer_and_title*(
    performer: string, title: string
): tuple[performer: Option[string], title: string] =
  var p = performer
  var t = title

  if performer in ["", "NA"]:
    let splitted = title.split("-", 1).map (s: string) => s.strip
    if splitted.len == 1:
      return (performer: none(string), title: title.strip)
    else:
      p = splitted[0]
      t = splitted[1]

  return (performer: some(p.strip), title: strip t.strip.replace p.strip & " -")
