# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import
  std/[
    json, math, nre, strutils, sets, hashes, options, sugar, sequtils, base64, uri,
    algorithm, enumerate,
  ]

import common
import cache
import commands

type BandcampUrl* = distinct string

proc url_regex*(url: BandcampUrl): Regex =
  return re"https?:\/\/((?:\w|-)+)\.bandcamp\.com\/?$"

func album_cache_item(au: string): JsonNode =
  %*{"type": "album", "url": au}

func track_cache_item(tu: string): JsonNode =
  %*{"type": "track", "url": tu}

proc not_cached_albums_urls(items_collector: ItemsCollector[BandcampUrl]): seq[string] =
  let artist_page =
    "yt-dlp"
    .execute(
      @[
        "--flat-playlist",
        "--skip-download",
        "--dump-pages",
        $(items_collector.url.string.parse_uri / "music"),
        "--proxy",
        "",
      ]
    ).split_lines
    .filter((l: string) => is_some l.match re"[^\[].*")[0].decode

  var r: OrderedSet[string]
  for reg in [
    re("href=\"([^&\\n]+)&amp;tab=music"),
    re("\"(\\/(?:album|track)\\/[^\"]+)\""),
    re(";(\\/(?:album|track)\\/[^&\"]+)(?:&|\")"),
    re"page_url&quot;:&quot;([^&]+)&",
  ]:
    for m in artist_page.find_iter reg:
      let c = m.captures[0]
      let au = block:
        if c.starts_with "http":
          c
        else:
          $(items_collector.url.string.parse_uri / c)
      if au.album_cache_item notin items_collector.cache:
        r.incl au
  result = r.to_seq
  reverse result

proc cache_until_including*(
    items_collector: var ItemsCollector[BandcampUrl], last_album_url: string
) =
  for au in items_collector.not_cached_albums_urls:
    items_collector.cache.incl au.album_cache_item
    if au.split('/')[^1] == last_album_url.split('/')[^1]:
      break

iterator items*(items_collector: var ItemsCollector[BandcampUrl]): Item =
  for au in items_collector.not_cached_albums_urls:
    let single = "/track/" in au
    let thumbnail_id = ($au.hash).strip(trailing = false, chars = {'-'})
    let tracks_urls = block:
      if single:
        @[au]
      else:
        let tracks_urls_output_lines = block:
          try:
            split_lines "yt-dlp".execute @[
              "--flat-playlist", "--print", "url", "--proxy", "", au
            ]
          except CommandFatalError:
            continue
        tracks_urls_output_lines.filter (l: string) => l.starts_with "http"

    for i, tu in enumerate tracks_urls:
      if tu.track_cache_item in items_collector.cache:
        continue
      let track_info_output_lines = split_lines "yt-dlp".execute @[
        "--skip-download", "--print", "uploader", "--print", "title", "--print",
        "duration", "--proxy", "", tu,
      ]

      let decoupled = decouple_performer_and_title(
        performer = track_info_output_lines[0], title = track_info_output_lines[1]
      )
      yield Item(
        url: tu,
        performer: decoupled.performer,
        title: decoupled.title,
        duration: int parse_float track_info_output_lines[2],
        cache_items:
          if (i == tracks_urls.len - 1) and not single:
            @[tu.track_cache_item, au.album_cache_item]
          else:
            @[tu.track_cache_item],
        thumbnail_id: thumbnail_id,
        keep_thumbnail: i != tracks_urls.len - 1,
        need_proxy: false,
      )
