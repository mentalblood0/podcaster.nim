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
  tuple[cache: Cache, downloader: Downloader, uploader: Uploader, from_first: bool]

proc remove_thumbnails(paths: seq[Path]) =
  for p in paths:
    p.remove_file

proc upload_bandcamp(podcaster: var Podcaster, url: Uri): seq[Path] =
  if url in podcaster.cache:
    return

  var parsed: Parsed
  while true:
    try:
      parsed = parse url
      break
    except BandcampError:
      podcaster.cache.incl url
      return

  if parsed.kind == pPlaylist:
    if parsed.playlist.kind == pBandcampAlbum:
      log(lvl_info, &"<-- {parsed.playlist.url}")
    var thumbnails_to_remove: seq[Path]
    for url in parsed.playlist.items podcaster.from_first:
      thumbnails_to_remove &= podcaster.upload_bandcamp url
    remove_thumbnails thumbnails_to_remove
    if parsed.playlist.kind == pBandcampAlbum:
      podcaster.cache.incl url
  elif parsed.kind == pMedia:
    let a = block:
      try:
        podcaster.downloader.download_thumbnail parsed.media
        result.add parsed.media.thumbnail_path.Path
        podcaster.downloader.download parsed.media
      except BandcampError:
        podcaster.cache.incl url
        return
    podcaster.uploader.upload(
      a, parsed.media.performer, parsed.media.title, parsed.media.thumbnail_path
    )
    podcaster.cache.incl url

proc upload_nonbandcamp(podcaster: var Podcaster, url: Uri): bool =
  result = false
  var parsed: Parsed
  while true:
    try:
      parsed = parse url
      break
    except DurationNotAvailableError:
      return
    except SslUnexpectedEofError, UnableToConnectToProxyError:
      continue

  if parsed.kind == pPlaylist:
    for url in parsed.playlist.items podcaster.from_first:
      if podcaster.upload_nonbandcamp url:
        return
  elif parsed.kind == pMedia:
    if parsed.media in podcaster.cache:
      return not podcaster.from_first
    let a = block:
      try:
        podcaster.downloader.download_thumbnail parsed.media
        podcaster.downloader.download parsed.media
      except BandcampError, DurationNotAvailableError:
        podcaster.cache.incl parsed.media
        return
    podcaster.uploader.upload(
      a, parsed.media.performer, parsed.media.title, parsed.media.thumbnail_path
    )
    podcaster.cache.incl parsed.media
    parsed.media.thumbnail_path.Path.remove_file

proc upload(podcaster: var Podcaster, url: Uri) =
  if url.is_bandcamp_url:
    discard podcaster.upload_bandcamp url
  else:
    discard podcaster.upload_nonbandcamp url

proc get_from_first(cache: Cache): bool =
  let from_first_arg = get_env "podcaster_from_first"
  if from_first_arg.len > 0:
    case from_first_arg
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
      from_first: get_from_first(cache),
    )

    try:
      podcaster.upload url
    except:
      remove_temp_files()
      raise
