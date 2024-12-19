# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import std/[strformat, json, math, nre, strutils, sets, hashes, options]

import common
import cache
import commands

type
  IntermediateItem = tuple[url: string, title: string, duration: int]

  YoutubeUrl* = distinct string

func cache_item(ii: IntermediateItem): JsonNode =
  %*{"title": ii.title, "duration": ii.duration}

iterator items*(playlist_url: YoutubeUrl): Item =
  var cache = block:
    let m = playlist_url.string.match re"https?:\/\/(?:www\.)?youtube\.com\/@?((?:\w|\.)+)\/(?:(?:videos)|(?:playlist\?list=(?:\w|-)+))\/?$"
    if not is_some m:
      raise new_exception(
        UnsupportedUrlError,
        &"Youtube module does not support URL '{playlist_url.string}'",
      )
    new_cache m.get.captures[0]

  let intermediate_items = block:
    var r: OrderedSet[IntermediateItem]
    let output_lines = (
      "yt-dlp".execute @[
        "--flat-playlist", "--playlist-items", "::-1", "--print", "url", "--print",
        "title", "--print", "duration", playlist_url.string,
      ]
    ).split_lines
    for i in 0 .. (int math.floor output_lines.len / 3 - 1):
      let title = output_lines[i + 1]
      let duration = parse_int output_lines[i + 2]
      let ii = (url: output_lines[i], title: title, duration: duration)
      if ii.cache_item notin cache:
        r.incl ii
    r

  if intermediate_items.len > 0:
    let performer = strip "yt-dlp".execute @[
      "--skip-download", "--playlist-items", "1", "--print", "playlist_uploader",
      playlist_url.string,
    ]
    for ii in intermediate_items:
      let decoupled = decouple_performer_and_title(performer, ii.title)
      yield Item(
        url: ii.url,
        performer: decoupled.performer,
        title: decoupled.title,
        duration: ii.duration,
      )
      cache.incl ii.cache_item
