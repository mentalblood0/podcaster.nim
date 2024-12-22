# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import std/[strformat, json, math, nre, strutils, sets, hashes, options, logging, os]

import common
import cache
import commands

type
  IntermediateItem = tuple[url: string, title: string, duration: int]

  YoutubeUrl* = distinct string

proc url_regex*(url: YoutubeUrl): Regex =
  return
    re"https?:\/\/(?:www\.)?youtube\.com\/@?((?:\w|\.)+)\/(?:(?:videos)|(?:playlist\?list=(?:\w|-)+))\/?$"

func cache_item(ii: IntermediateItem): JsonNode =
  %*{"title": ii.title, "duration": ii.duration}

proc get_intermediate_items(
    items_collector: ItemsCollector[YoutubeUrl]
): OrderedSet[IntermediateItem] =
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
      result.incl ii
    i += 3

proc cache_until_including*(
    items_collector: var ItemsCollector[YoutubeUrl], last_url: string
) =
  for ii in items_collector.get_intermediate_items:
    items_collector.cache.incl ii.cache_item
    if ii.url == last_url:
      break

iterator items*(items_collector: var ItemsCollector[YoutubeUrl]): Item =
  let intermediate_items = items_collector.get_intermediate_items()

  if intermediate_items.len > 0:
    let performer = strip "yt-dlp".execute @[
      "--skip-download", "--playlist-items", "1", "--print", "playlist_uploader",
      items_collector.url.string,
    ]
    lvl_info.log &"{performer} items not in cache: {intermediate_items.len}"
    for ii in intermediate_items:
      let decoupled = decouple_performer_and_title(performer, ii.title)
      yield Item(
        url: ii.url,
        performer: decoupled.performer,
        title: decoupled.title,
        duration: ii.duration,
        cache_items: @[ii.cache_item],
        thumbnail_id: ($ii.hash).strip(trailing = false, chars = {'-'}),
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
