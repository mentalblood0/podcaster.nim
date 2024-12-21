# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import
  std/[
    strformat, json, math, nre, strutils, sets, hashes, options, logging, os, sugar,
    sequtils, base64, uri, algorithm, enumerate,
  ]

import common
import cache
import commands
import logging

type
  IntermediateItem = tuple[url: string, title: string, duration: int]

  BandcampUrl* = distinct string

proc new_items_collector*(artist_url: BandcampUrl): ItemsCollector[BandcampUrl] =
  let m = artist_url.string.match re"https?:\/\/((?:\w|-)+)\.bandcamp\.com\/music\/?$"
  if not is_some m:
    raise new_exception(
      UnsupportedUrlError, &"Bandcamp module does not support URL '{artist_url.string}'"
    )
  result.url = artist_url
  result.cache = new_cache m.get.captures[0]

func album_cache_item(au: string): JsonNode =
  %*{"type": "album", "url": au}

func track_cache_item(tu: string): JsonNode =
  %*{"type": "track", "url": tu}

iterator items*(items_collector: var ItemsCollector[BandcampUrl]): Item =
  let page =
    "yt-dlp"
    .execute(
      @[
        "--flat-playlist", "--skip-download", "--dump-pages", items_collector.url.string
      ]
    ).split_lines
    .filter((l: string) => is_some l.match re"[^\[].*")[0].decode

  let albums_urls = block:
    var r: OrderedSet[string]
    for reg in [
      re("href=\"([^&\\n]+)&amp;tab=music"),
      re("\"(\\/(?:album|track)\\/[^\"]+)\""),
      re(";(\\/(?:album|track)\\/[^&\"]+)(?:&|\")"),
      re"page_url&quot;:&quot;([^&]+)&",
    ]:
      for m in page.find_iter reg:
        let c = m.captures[0]
        let au = block:
          if c.starts_with "http":
            c
          else:
            $items_collector.url.string.parse_uri / c
        if au.album_cache_item notin items_collector.cache:
          r.incl au
    var r_seq = r.to_seq
    reverse r_seq
    r_seq

  for au in albums_urls:
    let tracks_urls_output_lines = block:
      try:
        split_lines "yt-dlp".execute @[
          "--flat-playlist", "--print", "url", items_collector.url.string
        ]
      except CommandFatalError:
        continue

    let tracks_urls =
      tracks_urls_output_lines.filter (l: string) => l.starts_with "http"

    for i, tu in enumerate tracks_urls:
      if tu.track_cache_item in items_collector.cache:
        continue
      let tracks_info_output_lines = split_lines "yt-dlp".execute @[
        "--skip-download", "--print", "uploader", "--print", "title", "--print",
        "duration",
      ]

      var i = 0
      while i + 2 < tracks_info_output_lines.len:
        let decoupled = decouple_performer_and_title(
          tracks_info_output_lines[i], tracks_info_output_lines[i + 1]
        )
        yield Item(
          url: tu,
          performer: decoupled.performer,
          title: decoupled.title,
          duration: int parse_float tracks_info_output_lines[i + 2],
          cache_items:
            if i == tracks_urls.len - 1:
              @[tu.track_cache_item, au.album_cache_item]
            else:
              @[tu.track_cache_item],
        )

proc on_uploaded*(
    items_collector: var ItemsCollector[BandcampUrl],
    item: Item,
    downloaded: Option[Downloaded] = none(Downloaded),
) =
  for c in item.cache_items:
    items_collector.cache.incl c
