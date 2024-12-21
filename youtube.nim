# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import std/[strformat, json, math, nre, strutils, sets, hashes, options, logging, os]

import common
import cache
import commands
import logging

type
  IntermediateItem = tuple[url: string, title: string, duration: int]

  YoutubeUrl* = distinct string

func cache_item(ii: IntermediateItem): JsonNode =
  %*{"title": ii.title, "duration": ii.duration}

proc new_items_collector*(playlist_url: YoutubeUrl): ItemsCollector[YoutubeUrl] =
  let m = playlist_url.string.match re"https?:\/\/(?:www\.)?youtube\.com\/@?((?:\w|\.)+)\/(?:(?:videos)|(?:playlist\?list=(?:\w|-)+))\/?$"
  if not is_some m:
    raise new_exception(
      UnsupportedUrlError,
      &"Youtube module does not support URL '{playlist_url.string}'",
    )
  result.url = playlist_url
  result.cache = new_cache m.get.captures[0]

iterator items*(items_collector: var ItemsCollector[YoutubeUrl]): Item =
  let intermediate_items = block:
    var r: OrderedSet[IntermediateItem]
    let output_lines = (
      "yt-dlp".execute @[
        "--flat-playlist", "--playlist-items", "::-1", "--print", "url", "--print",
        "title", "--print", "duration", items_collector.url.string,
      ]
    ).split_lines
    var i = 0
    while i + 2 < output_lines.len:
      let ii = (
        url: output_lines[i],
        title: output_lines[i + 1],
        duration: int parse_float output_lines[i + 2],
      )
      if ii.cache_item notin items_collector.cache:
        r.incl ii
      i += 3
    r

  lvl_info.log &"items not in cache: {intermediate_items.len}"

  if intermediate_items.len > 0:
    let performer = strip "yt-dlp".execute @[
      "--skip-download", "--playlist-items", "1", "--print", "playlist_uploader",
      items_collector.url.string,
    ]
    for ii in intermediate_items:
      let decoupled = decouple_performer_and_title(performer, ii.title)
      yield Item(
        url: ii.url,
        performer: decoupled.performer,
        title: decoupled.title,
        duration: ii.duration,
        cache_items: @[ii.cache_item],
      )

proc on_uploaded*(
    items_collector: var ItemsCollector[YoutubeUrl],
    item: Item,
    downloaded: Option[Downloaded] = none(Downloaded),
) =
  for c in item.cache_items:
    items_collector.cache.incl c
  if downloaded.is_some:
    downloaded.get.thumbnail_path.remove_file
