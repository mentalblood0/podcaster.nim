# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import xxhash
import nint128

import std/base64
import std/strformat
import std/sugar
import std/algorithm
import std/strtabs
import std/os
import std/exitprocs
import std/json
import std/math
import std/streams
import std/paths
import std/times
import std/nre
import std/sets
import std/tables
import std/sequtils
import std/strutils
import std/osproc
import std/uri
import std/logging

import logging

let page_regex = re"[^\[].*"
let bandcamp_albums_urls_regexes =
  @[
    re("href=\"([^&\\n]+)&amp;tab=music"),
    re("\"(\\/(?:album|track)\\/[^\"]+)\""),
    re(";(\\/(?:album|track)\\/[^&\"]+)(?:&|\")"),
    re"page_url&quot;:&quot;([^&]+)&",
  ]
let bandcamp_url_regex = re"https?:\/\/(?:\w+\.)?bandcamp\.com.*$"
let bandcamp_artist_url_regex =
  re"https?:\/\/(?:\w+\.)?bandcamp\.com(?:\/|(?:\/music\/?))?$"
let bandcamp_album_url_regex =
  re"https?:\/\/(?:\w+\.)?bandcamp\.com\/album\/(?:(?:(?:\w|-)+)|(?:-*\d+))\/?$"
let bandcamp_track_url_regex = re"https?:\/\/(?:\w+\.)?bandcamp\.com\/track\/[^\/]+\/?$"
let youtube_channel_url_regex =
  re"https?:\/\/(?:www\.)?youtube\.com\/@?\w+(:?(?:\/?)|(?:\/videos\/?)|(?:\/playlists\/?)|(?:\/streams\/?))$"
let youtube_playlist_url_regex =
  re"https?:\/\/(?:www\.)?youtube\.com\/playlist\?list=\w+\/?$"
let youtube_video_url_regex = re"https?:\/\/(?:www\.)?youtube\.com\/watch\?v=.*$"

proc is_bandcamp_url*(url: Uri): bool =
  is_some ($url).match bandcamp_url_regex

var ytdlp_proxy* = ""

var temp_files_dir* = "/mnt/tmpfs".Path
var temp_files: HashSet[string]

proc new_temp_file(name: string): string =
  let path = string temp_files_dir / name.Path
  temp_files.incl path
  return path

proc new_temp_file(u: Url, postfix: string): string =
  new_temp_file encode($u.string.XXH3_128bits.to_bytes_b_e, safe = true).replace(
    "=", ""
  ) & "_" & postfix

proc remove_temp_files*() =
  for p in temp_files:
    p.remove_file

add_exit_proc remove_temp_files
set_control_c_hook () {.noconv.} => quit()

type PlaylistKind* = enum
  pBandcampAlbum
  pBandcampArtist
  pYoutubePlaylist
  pYoutubeChannel

type Playlist* = tuple[url: Uri, title, uploader: string, kind: PlaylistKind]

func hash*(p: Playlist): string =
  let id = %*{"title": p.title, "uploader": p.uploader}
  return ($id).XXH3_128bits.to_bytes_b_e.encode(safe = true).replace("=", "")

proc new_playlist*(url: Uri): Playlist =
  if is_some ($url).match bandcamp_album_url_regex:
    result.kind = pBandcampAlbum
  elif is_some ($url).match bandcamp_artist_url_regex:
    result.kind = pBandcampArtist
  elif is_some ($url).match youtube_channel_url_regex:
    result.kind = pYoutubeChannel
  elif is_some ($url).match youtube_playlist_url_regex:
    result.kind = pYoutubePlaylist
  else:
    raise new_exception(
      ValueError, "No regular expression match supposedly playlist URL \"" & $url & "\""
    )

  const fields = ["playlist_title", "playlist_uploader"]
  let args = block:
    var r = @["--skip-download", "--playlist-items", "1"]
    for k in fields:
      r.add "--print"
      r.add k
    r.add $url
    r
  let d = to_table fields.zip exec_process(
    "yt-dlp", args = args, options = {po_use_path}
  ).split_lines
  result.url = url
  result.title = d["playlist_title"]
  result.uploader = d["playlist_uploader"]

proc download_page(url: Uri): string =
  let output_lines = exec_process(
    "yt-dlp",
    args = ["--flat-playlist", "--skip-download", "--dump-pages", $(url / "music")],
    options = {po_use_path},
  ).split_lines
  for l in output_lines:
    if is_some l.match page_regex:
      return decode l

iterator items*(playlist: Playlist, reverse_order: bool = false): Uri =
  if playlist.kind in [pYoutubeChannel, pYoutubeChannel, pBandcampAlbum]:
    let output_lines = exec_process(
      "yt-dlp",
      args = block:
        var a = @["--flat-playlist", "--print", "url", $playlist.url]
        if reverse_order:
          a &= @["--playlist-items", "::-1"]
        a,
      options = {po_use_path},
    ).split_lines
    for l in output_lines:
      if l.starts_with "http":
        yield parse_uri l
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
    uploader: string,
    duration: Duration,
    thumbnail_path: string,
  ]

func hash*(m: Media): string =
  let id = %*{"title": m.title, "uploaded": to_unix to_time m.uploaded}
  return ($id).XXH3_128bits.to_bytes_b_e.encode(safe = true).replace("=", "")

proc new_temp_file(m: Media, ext: string): string =
  let p = m.hash.Path.add_file_ext(ext).string
  discard new_temp_file &"{p}.part"
  return new_temp_file p

proc execute(command: string, args: seq[string]): string =
  log(lvl_debug, &"{command} {args}")
  let p = start_process(
    command,
    args = args,
    options = {po_use_path, po_std_err_to_std_out},
    env = new_string_table({"http_proxy": ytdlp_proxy, "https_proxy": ytdlp_proxy}),
  )
  try:
    do_assert p.wait_for_exit == 0
  except AssertionDefect:
    log(lvl_warn, &"{command} {args} failed:\n{p.output_stream.read_all}")
    raise
  result = p.output_stream.read_all
  p.close

proc new_media*(url: Uri, scale_width: int): Media =
  result.url = url
  let dict = block:
    const fields = ["title", "upload_date", "timestamp", "duration", "thumbnail"]
    let args = block:
      var r = @["--skip-download"]
      for k in fields:
        r.add "--print"
        r.add k
      r.add $url
      r
    to_table fields.zip split_lines "yt-dlp".execute args
  result.title = dict["title"]
  result.duration = init_duration(seconds = int parse_float dict["duration"])
  result.uploaded = block:
    try:
      utc from_unix parse_int dict["timestamp"]
    except ValueError:
      dict["upload_date"].parse "yyyymmdd", utc()
  result.thumbnail_path = block:
    let thumbnail_url = dict["thumbnail"].Url
    let scaled_path = thumbnail_url.new_temp_file "scaled.png"
    if not scaled_path.file_exists:
      let original_path = thumbnail_url.new_temp_file "original.jpg"
      discard "yt-dlp".execute @[
        $url,
        "--write-thumbnail",
        "--skip-download",
        "-o",
        $original_path.change_file_ext "",
      ]
      let converted_path = thumbnail_url.new_temp_file "converted.png"
      discard "ffmpeg".execute @["-i", original_path, converted_path]
      discard "ffmpeg".execute @[
        "-i", converted_path, "-vf", &"scale={scale_width}:-1", scaled_path
      ]
      original_path.remove_file
      converted_path.remove_file
    scaled_path

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

proc parse*(url: Uri, thumbnail_scale_width: int): Parsed =
  if (($url).match bandcamp_track_url_regex).is_some or
      (($url).match youtube_video_url_regex).is_some:
    return Parsed(kind: pMedia, media: new_media(url, thumbnail_scale_width))
  return Parsed(kind: pPlaylist, playlist: new_playlist url)

type Audio* = tuple[path: string, duration: Duration]

proc new_temp_file(a: Audio, prefix: string): string =
  return new_temp_file &"{prefix}_{a.path.extract_file_name}"

proc new_temp_file(a: Audio, part: int): string =
  return a.new_temp_file &"part{part}"

proc audio*(media: Media, kilobits_per_second: Option[int] = none(int)): Audio =
  let format =
    if is_some kilobits_per_second:
      &"ba[abr<={kilobits_per_second.get}]/wa[abr>={kilobits_per_second.get}]"
    else:
      "mp3"
  let temp_path = media.new_temp_file "mp3"
  log(lvl_info, &"<-- {media.title}")
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
      start_process(
        "ffmpeg",
        args =
          @[
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
          ],
        options = {po_use_path, po_std_err_to_std_out},
      )
  for i, p in processes:
    do_assert p.wait_for_exit == 0
    p.close
    yield (
      path: a.new_temp_file(i + 1),
      duration: init_duration(seconds = int a.duration.in_seconds / parts),
    )
  a.path.remove_file

iterator split*(a: Audio, part_size: int): Audio =
  for r in a.split_into int ceil a.path.get_file_size / part_size:
    yield r
