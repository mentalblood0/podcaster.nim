# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import std/[strformat, sugar, os, json, math, nre, sequtils, strutils, logging, sets]

import common
import cache
import commands
import tempfiles
import downloader

type ItermediateItem = tuple[url: string, title: string, duration: int, hash: string]

iterator items*(downloader: Downloader, playlist_url: string): Item =
  var cache = block:
    let m = playlist_url.match re"https?:\/\/(?:www\.)?youtube\.com\/@?((?:\w|\.)+)\/(?:(?:videos)|(?:playlist\?list=(?:\w|-)+))\/?$"
    if not is_some m:
      raise new_exception(
        UnsupportedUrlError, &"Youtube module does not support URL '{playlist_url}'"
      )
    new_cache m.get.captures[0]

  let intermediate_items = block:
    var r: OrderedSet[ItermediateItem]
    let output_lines = (
      "yt-dlp".execute @[
        "--flat-playlist", "--print", "url", "--print", "title", "--print", "duration",
        playlist_url,
      ]
    ).split_lines
    for i in 0 .. (int math.floor output_lines.len / 3 - 1):
      let title = output_lines[i + 1]
      let duration = parse_int output_lines[i + 2]
      let hash = cache.hash($ %*{"title": title, "duration": duration})
      if hash notin cache:
        r.incl (url: output_lines[i], title: title, duration: duration, hash: hash)
    r

  if intermediate_items.len > 0:
    let performer = strip "yt-dlp".execute @[
      "--skip-download", "--playlist-items", "1", "--print", "playlist_uploader",
      playlist_url,
    ]
    for ii in intermediate_items:
      let thumbnail_path = downloader.download_thumbnail(ii.url, ii.hash)
      let audio_path = downloader.download_audio(ii.url, ii.hash)
      yield Item(
        audio_path: audio_path,
        thumbnail_path: thumbnail_path,
        performer: performer,
        title: ii.title,
        duration: ii.duration,
      )
      thumbnail_path.remove_file
      audio_path.remove_file
