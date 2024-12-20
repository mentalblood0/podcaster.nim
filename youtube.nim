# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import std/[strformat, json, math, nre, strutils, sets, hashes, options, logging]

import common
import cache
import commands
import logging

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
    var i = 0
    while i + 2 < output_lines.len:
      let title = output_lines[i + 1]
      let duration = int parse_float output_lines[i + 2]
      let ii = (url: output_lines[i], title: title, duration: duration)
      if ii.cache_item notin cache:
        lvl_debug.log &"not in cache: {ii}"
        r.incl ii
      i += 3
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
