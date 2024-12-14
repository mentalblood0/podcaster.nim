import
  std/[
    files, sets, uri, paths, sequtils, options, strutils, cmdline, logging, strformat,
    envvars,
  ]

import ytdlp
import Cache
import Downloader
import Uploader

type Podcaster* =
  tuple[cache: Cache, downloader: Downloader, uploader: Uploader, reverse_order: bool]

proc remove_thumbnails(paths: seq[Path]) =
  for p in paths:
    p.remove_file

proc upload*(podcaster: var Podcaster, url: Uri): seq[Path] =
  let is_bandcamp = is_bandcamp_url url
  if is_bandcamp and (url in podcaster.cache):
    return

  let parsed = block:
    var r: Parsed
    while true:
      try:
        r = parse(url)
        break
      except BandcampError, DurationNotAvailableError:
        break
      except SslUnexpectedEofError, UnableToConnectToProxyError:
        continue
    r

  if parsed.kind == pPlaylist:
    if parsed.playlist.kind notin [pBandcampArtist, pYoutubeChannel]:
      log(lvl_info, &"<-- {parsed.playlist.uploader} - {parsed.playlist.title}")
    remove_thumbnails block:
      var r: seq[Path]
      for url in parsed.playlist.items podcaster.reverse_order:
        if is_bandcamp and url notin podcaster.cache:
          r &= podcaster.upload url
          podcaster.cache.incl url
        else:
          remove_thumbnails podcaster.upload url
      r
    if is_bandcamp and parsed.playlist.kind != pBandcampArtist:
      podcaster.cache.incl url
  elif parsed.kind == pMedia:
    if parsed.media in podcaster.cache:
      if not podcaster.reverse_order and not is_bandcamp:
        return
      return
    let audio = block:
      var r: Audio
      while true:
        try:
          podcaster.downloader.download_thumbnail parsed.media
          r = podcaster.downloader.download parsed.media
          break
        except BandcampError, DurationNotAvailableError:
          break
        except SslUnexpectedEofError, UnableToConnectToProxyError:
          continue
      r
    podcaster.uploader.upload(audio, parsed.media.title, parsed.media.thumbnail_path)
    if is_bandcamp:
      podcaster.cache.incl url
    else:
      podcaster.cache.incl parsed.media
    result.add parsed.media.thumbnail_path.Path

proc get_reverse_order(cache: Cache): bool =
  let reverse_order_arg = get_env "podcaster_from_first"
  if reverse_order_arg.len > 0:
    case reverse_order_arg
    of "true":
      return true
    of "false":
      return false
  return cache.hashes.len == 0

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
    let chat_id = splitted_arg[0]
    let url = parse_uri splitted_arg[1]

    let cache = new_cache url

    var podcaster = (
      cache: cache,
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
        thumbnail_scale_width: 200,
      ),
      uploader: (token: get_env "podcaster_token", chat_id: chat_id),
      reverse_order: get_reverse_order(cache),
    )

    try:
      discard podcaster.upload url
    except:
      remove_temp_files()
      raise
