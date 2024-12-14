import std/files
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

proc remove_thumbnails(paths: seq[Path]) =
  for p in paths:
    p.remove_file

proc upload*(podcaster: var Podcaster, url: Uri): seq[Path] =
  let is_bandcamp = is_bandcamp_url url
  if is_bandcamp and (url in podcaster.cache):
    return

  let parsed =
    try:
      parse(url, 200)
    except BandcampError:
      return

  if parsed.kind == pPlaylist:
    if parsed.playlist.kind notin [pBandcampArtist, pYoutubeChannel]:
      log(lvl_info, &"<-- {parsed.playlist.uploader} - {parsed.playlist.title}")

    var thumbnails_to_remove: seq[Path]
    for url in parsed.playlist:
      if is_bandcamp and url notin podcaster.cache:
        thumbnails_to_remove &= podcaster.upload url
        podcaster.cache.incl url
      else:
        thumbnails_to_remove &= podcaster.upload url
    remove_thumbnails thumbnails_to_remove

    if is_bandcamp and parsed.playlist.kind != pBandcampArtist:
      podcaster.cache.incl url
  elif parsed.kind == pMedia and parsed.media notin podcaster.cache:
    let audio =
      try:
        podcaster.downloader.download parsed.media
      except BandcampError:
        return
    podcaster.uploader.upload(audio, parsed.media.title, parsed.media.thumbnail_path)
    if is_bandcamp:
      podcaster.cache.incl url
    else:
      podcaster.cache.incl parsed.media
    result.add parsed.media.thumbnail_path.Path

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

    try:
      discard podcaster.upload url
    except:
      remove_temp_files()
      raise
