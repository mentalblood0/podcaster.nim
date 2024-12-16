# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import xxhash
import nint128

import
  std/[
    base64, strformat, sugar, algorithm, strtabs, os, exitprocs, json, math, streams,
    paths, times, nre, sets, tables, sequtils, strutils, osproc, uri, logging,
  ]

import logging

let page_regex* = re"[^\[].*"
let bandcamp_albums_urls_regexes* =
  @[
    re("href=\"([^&\\n]+)&amp;tab=music"),
    re("\"(\\/(?:album|track)\\/[^\"]+)\""),
    re(";(\\/(?:album|track)\\/[^&\"]+)(?:&|\")"),
    re"page_url&quot;:&quot;([^&]+)&",
  ]
let bandcamp_url_regex* = re"https?:\/\/(?:((?:\w|-)+)\.)?bandcamp\.com.*$"
let bandcamp_artist_url_regex* =
  re"https?:\/\/(?:(?:\w|-)+\.)?bandcamp\.com(?:\/|(?:\/music\/?))?$"
let bandcamp_album_url_regex* =
  re"https?:\/\/(?:(?:\w|-)+\.)?bandcamp\.com\/album\/(?:(?:(?:\w|-)+)|(?:-*\d+))\/?$"
let bandcamp_track_url_regex* =
  re"https?:\/\/(?:(?:\w|-)+\.)?bandcamp\.com\/track\/[^\/]+\/?$"
let youtube_channel_url_regex* =
  re"https?:\/\/(?:www\.)?youtube\.com\/@?((?:\w|\.)+)(:?(?:\/?)|(?:\/shorts\/?)|(?:\/videos\/?)|(?:\/playlists\/?)|(?:\/streams\/?))$"
let youtube_topic_url_regex* =
  re"https?:\/\/(?:www\.)?youtube\.com\/channel\/\w+(:?\/?|(?:\/videos\/?))?"
let youtube_playlist_url_regex* =
  re"https?:\/\/(?:www\.)?youtube\.com\/playlist\?list=(?:\w|-)+\/?$"
# https://www.youtube.com/playlist?list=OLAK5uy_lmrAEUvtxIzatZWTVYhG-LIOmj3lsHugQ
let youtube_video_url_regex* = re"https?:\/\/(?:www\.)?youtube\.com\/watch\?v=.*$"
let youtube_short_url_regex* = re"https?:\/\/(?:www\.)?youtube\.com\/shorts\/\w+$"

proc is_bandcamp_url*(url: Uri): bool =
  is_some ($url).match bandcamp_url_regex

var ytdlp_proxy* = ""

var temp_files_dir* = "/mnt/tmpfs".Path
var temp_files: HashSet[string]

proc new_temp_file(name: string): string =
  let path = string temp_files_dir / name.Path
  temp_files.incl path
  return path

func safe_hash*(u: Uri): string =
  ($u).XXH3_128bits.to_bytes_b_e.encode(safe = true).replace("=", "")

proc new_temp_file(u: Uri, postfix: string): string =
  new_temp_file u.safe_hash & "_" & postfix

proc remove_temp_files*() =
  for p in temp_files:
    p.remove_file

add_exit_proc remove_temp_files
set_control_c_hook () {.noconv.} => quit(1)

type
  BandcampError* = object of AssertionDefect
  BandcampNoVideoFormatsFoundError* = object of BandcampError
  BandcampNoTracksOnPageError* = object of BandcampError
  DurationNotAvailableError* = object of ValueError
  SslUnexpectedEofError* = object of AssertionDefect
  UnableToConnectToProxyError* = object of AssertionDefect
  ReadTimedOutError* = object of AssertionDefect
  UnableToFetchPoTokenError* = object of AssertionDefect

proc check_substring_exceptions(command_output: string) =
  if is_some command_output.match re"ERROR: \[Bandcamp\] \d+: No video formats found!;":
    raise new_exception(BandcampNoVideoFormatsFoundError, command_output)
  if "The page doesn't contain any tracks;" in command_output:
    raise new_exception(BandcampNoTracksOnPageError, command_output)
  if "SSL: UNEXPECTED_EOF_WHILE_READING" in command_output:
    raise new_exception(SslUnexpectedEofError, command_output)
  if "Unable to connect to proxy" in command_output:
    raise new_exception(UnableToConnectToProxyError, command_output)
  if "Read timed out." in command_output:
    raise new_exception(ReadTimedOutError, command_output)
  if "Unable to fetch PO Token for mweb client" in command_output:
    raise new_exception(UnableToFetchPoTokenError, command_output)
  raise

type CommandProcess = tuple[command: string, args: seq[string], process: Process]

func command_string(p: CommandProcess): string =
  p.command & " " & p.args.map(quote_shell).join(" ")

proc new_command_process(command: string, args: seq[string]): CommandProcess =
  result = (
    command: command,
    args: args,
    process: start_process(
      command,
      args = args,
      options = {po_use_path, po_std_err_to_std_out},
      env = new_string_table({"http_proxy": ytdlp_proxy, "https_proxy": ytdlp_proxy}),
    ),
  )
  log(lvl_debug, result.command_string)

proc wait_for_exit(p: CommandProcess): string =
  try:
    do_assert p.process.wait_for_exit == 0
  except AssertionDefect:
    result = p.process.output_stream.read_all
    log(lvl_warn, &"command '{p.command_string}' failed:\n{result}")
    check_substring_exceptions(result)
    raise
  result = p.process.output_stream.read_all
  p.process.close

proc execute(command: string, args: seq[string]): string =
  while true:
    try:
      return wait_for_exit command.new_command_process args
    except SslUnexpectedEofError, UnableToConnectToProxyError, ReadTimedOutError,
        UnableToFetchPoTokenError:
      continue

type PlaylistKind* = enum
  pBandcampAlbum
  pBandcampArtist
  pYoutubePlaylist
  pYoutubeChannel

type Playlist* = tuple[url: Uri, kind: PlaylistKind]

proc new_playlist*(url: Uri): Playlist =
  result.url = url
  if is_some ($url).match bandcamp_album_url_regex:
    result.kind = pBandcampAlbum
  elif is_some ($url).match bandcamp_artist_url_regex:
    result.kind = pBandcampArtist
  elif is_some ($url).match youtube_channel_url_regex:
    result.kind = pYoutubeChannel
  elif is_some ($url).match youtube_topic_url_regex:
    result.kind = pYoutubeChannel
  elif is_some ($url).match youtube_playlist_url_regex:
    result.kind = pYoutubePlaylist
  else:
    raise new_exception(
      ValueError, "No regular expression match supposedly playlist URL \"" & $url & "\""
    )

proc download_page(url: Uri): string =
  let output_lines = exec_process(
    "yt-dlp",
    args = ["--flat-playlist", "--skip-download", "--dump-pages", $(url / "music")],
    options = {po_use_path},
  ).split_lines
  for l in output_lines:
    if is_some l.match page_regex:
      return decode l

iterator items*(playlist: Playlist, from_first: bool = false): Uri =
  log(
    lvl_debug, &"items for {playlist.kind} {playlist.url}, from_first is {from_first}"
  )
  if playlist.kind == pBandcampAlbum:
    let args = block:
      var a = @["--flat-playlist", "--print", "url", $playlist.url]
      if from_first:
        a &= @["--playlist-items", "::-1"]
      a
    let output_lines = block:
      try:
        split_lines "yt-dlp".execute args
      except BandcampError:
        @[]
    for l in output_lines:
      if l.starts_with "http":
        yield parse_uri l
  elif playlist.kind in [pYoutubeChannel, pYoutubePlaylist]:
    var i = 0
    while true:
      let step = if from_first: -1 else: 1
      let query =
        if from_first:
          &"{i - 1}:{i - 1}:{step}"
        else:
          &"{i}:{i + 1}:{step}"
      let output = (
        "yt-dlp".execute @[
          "--flat-playlist", "--print", "url", "--playlist-items", query, $playlist.url
        ]
      ).split_lines[0]
      if output == "":
        break
      yield parse_uri output
      i += step
  elif playlist.kind == pBandcampArtist:
    let page = download_page playlist.url
    var urls = block:
      var u: OrderedSet[Uri]
      for r in bandcamp_albums_urls_regexes:
        for m in page.find_iter r:
          let c = m.captures[0]
          u.incl block:
            if c.starts_with "http":
              parse_uri c
            else:
              playlist.url / c
      u.to_seq
    reverse urls
    for u in urls:
      yield u

type Media* =
  tuple[
    url: Uri,
    title: string,
    uploaded: DateTime,
    performer: Option[string],
    duration: Duration,
    thumbnail_url: Uri,
    thumbnail_path: string,
  ]

func log_string*(performer: Option[string], title: string): string =
  if is_some performer:
    return &"{performer.get} - {title}"
  else:
    return title

func log_string*(m: Media): string =
  log_string(m.performer, m.title)

func hash*(m: Media): string =
  let id = %*{"title": m.title, "uploaded": to_unix to_time m.uploaded}
  return ($id).XXH3_128bits.to_bytes_b_e.encode(safe = true).replace("=", "")

proc new_temp_file(m: Media, ext: string): string =
  let p = m.hash.Path.add_file_ext(ext).string
  discard new_temp_file &"{p}.part"
  return new_temp_file p

proc new_media*(url: Uri): Media =
  result.url = url
  let dict = block:
    const fields =
      ["title", "upload_date", "timestamp", "duration", "thumbnail", "uploader"]
    let args = block:
      var r = @["--skip-download"]
      for k in fields:
        r.add "--print"
        r.add k
      r.add $url
      r
    to_table fields.zip split_lines "yt-dlp".execute args

  let splitted = dict["title"].split("-", 1).map (s: string) => s.strip
  if not url.is_bandcamp_url or splitted.len == 1:
    if "uploader" notin dict or dict["uploader"] == "":
      result.performer = none(string)
      result.title = dict["title"]
    else:
      result.performer = some(dict["uploader"])
      result.title = dict["title"]
  else:
    result.performer = some(splitted[0])
    result.title = splitted[1]

  if dict["duration"] == "NA":
    raise new_exception(
      DurationNotAvailableError, &"Duration value not available for media at {url}"
    )
  result.duration = init_duration(seconds = int parse_float dict["duration"])
  result.uploaded = block:
    try:
      utc from_unix parse_int dict["timestamp"]
    except ValueError:
      dict["upload_date"].parse "yyyymmdd", utc()
  result.thumbnail_url = parse_uri dict["thumbnail"]
  result.thumbnail_path = result.thumbnail_url.new_temp_file "scaled.png"

proc download_thumbnail*(media: Media, scale_width: int) =
  if media.thumbnail_path.file_exists:
    return
  let possible_original_paths =
    ["jpg", "webp"].map (e: string) => media.thumbnail_url.new_temp_file "original." & e
  discard "yt-dlp".execute @[
    $media.url,
    "--write-thumbnail",
    "--skip-download",
    "-o",
    $possible_original_paths[0].change_file_ext "",
  ]
  let original_path = possible_original_paths.filter(file_exists)[0]
  let converted_path = media.thumbnail_url.new_temp_file "converted.png"
  discard "ffmpeg".execute @["-i", original_path, converted_path]
  discard "ffmpeg".execute @[
    "-i", converted_path, "-vf", &"scale={scale_width}:-1", media.thumbnail_path
  ]
  original_path.remove_file
  converted_path.remove_file

type
  ParsedKind* = enum
    pPlaylist
    pMedia

  Parsed* = ref ParsedObj

  ParsedObj* = object
    case kind*: ParsedKind
    of pPlaylist:
      playlist*: Playlist
    of pMedia:
      media*: Media

proc parse*(url: Uri): Parsed =
  log(lvl_debug, &"parse url '{url}'")
  if (($url).match bandcamp_track_url_regex).is_some or
      (($url).match youtube_video_url_regex).is_some or
      (($url).match youtube_short_url_regex).is_some:
    return Parsed(kind: pMedia, media: new_media(url))
  return Parsed(kind: pPlaylist, playlist: new_playlist url)

type Audio* = tuple[path: string, duration: Duration]

proc new_temp_file(a: Audio, postfix: string): string =
  return new_temp_file &"{a.path.split_file.name}_{postfix}.mp3"

proc new_temp_file(a: Audio, part: int): string =
  return a.new_temp_file &"part{part}"

proc audio*(media: Media, kilobits_per_second: Option[int] = none(int)): Audio =
  let format =
    if is_some kilobits_per_second:
      &"ba[abr<={kilobits_per_second.get}]/wa[abr>={kilobits_per_second.get}]"
    else:
      "mp3"
  let temp_path = media.new_temp_file ""
  lvl_info.log &"<-- {media.log_string}"
  discard "yt-dlp".execute @["-f", format, "-o", temp_path, $media.url]
  return (path: temp_path, duration: media.duration)

type ConversionParams* = tuple[bitrate: int, samplerate: int, channels: int]

proc convert*(a: Audio, cp: ConversionParams = (128, 44100, 2)): Audio =
  let converted_path = a.new_temp_file "converted"
  discard "ffmpeg".execute @[
    "-i",
    a.path,
    "-vn",
    "-ar",
    $cp.samplerate,
    "-ac",
    $cp.channels,
    "-b:a",
    $cp.bitrate,
    converted_path,
  ]
  a.path.remove_file
  return (path: converted_path, duration: a.duration)

iterator split_into(a: Audio, parts: int): Audio =
  let processes = collect:
    for i in 0 .. (parts - 1):
      "ffmpeg".new_command_process @[
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        $int floor a.duration.in_seconds / parts * float i,
        "-i",
        a.path,
        "-t",
        $int ceil a.duration.in_seconds / parts,
        "-acodec",
        "copy",
        a.new_temp_file i + 1,
      ]
  for i, p in processes:
    discard p.wait_for_exit
    yield (
      path: a.new_temp_file(i + 1),
      duration: init_duration(seconds = int a.duration.in_seconds / parts),
    )
  a.path.remove_file

iterator split*(a: Audio, part_size: int): Audio =
  for r in a.split_into int ceil a.path.get_file_size / part_size:
    yield r
