import std/uri
import std/paths
import std/sequtils
import std/options
import std/strutils
import std/cmdline
import std/logging
import std/strformat
import std/envvars

import ytdlp
import Cache
import Downloader
import Uploader

type Podcaster* = tuple[cache: Cache, downloader: Downloader, uploader: Uploader]

proc upload*(podcaster: var Podcaster, url: Uri) =
  let is_bandcamp = is_bandcamp_url url
  if is_bandcamp and (url in podcaster.cache):
    return

  log(lvl_info, &"<-- {url}")
  let parsed = parse(url, 200)

  if parsed.kind == pPlaylist:
    for url in parsed.playlist:
      if is_bandcamp and url notin podcaster.cache:
        podcaster.upload url
        podcaster.cache.incl url
      else:
        podcaster.upload url
    if is_bandcamp:
      podcaster.cache.incl url
  elif parsed.kind == pMedia and parsed.media notin podcaster.cache:
    let audio = podcaster.downloader.download parsed.media
    podcaster.uploader.upload(audio, parsed.media.title, parsed.media.thumbnail_path)
    if is_bandcamp:
      podcaster.cache.incl url
    else:
      podcaster.cache.incl parsed.media

when is_main_module:
  ytdlp_proxy = get_env "podcaster_http_proxy"
  temp_files_dir = Path get_env "podcaster_temp_dir"

  case get_env "podcaster_log_level"
  of "debug":
    set_log_filter lvl_debug
  of "info":
    set_log_filter lvl_info
  of "error":
    set_log_filter lvl_error

  for i in 1 .. param_count():
    let splitted_arg = param_str(i).split(':', 1)
    let chat_id = parse_int splitted_arg[0]
    let url = parse_uri splitted_arg[1]

    var podcaster = (
      cache: new_cache url,
      downloader: (
        bitrate: block:
          let bitrate_env = get_env "podcaster_download_bitrate"
          if bitrate_env.len > 0:
            some parse_int bitrate_env
          else:
            none(int),
        conversion_params: block:
          let convert_env = get_env "podcaster_convert"
          if convert_env.len > 0:
            let splitted = convert_env.split(':').map parse_int
            some (bitrate: splitted[0], samplerate: splitted[1], channels: splitted[2])
          else:
            none(ConversionParams),
      ),
      uploader: (token: get_env "podcaster_token", chat_id: chat_id),
    )

    podcaster.upload url
