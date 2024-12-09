# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import xxhash
import nint128

import std/base64
import std/strformat
import std/sugar
import std/os
import std/exitprocs
import std/json
import std/math
import std/httpclient
import std/files
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
let duration_regex = re"time=(?P<hours>\d+):(?P<minutes>\d+):(?P<seconds>\d+)\.\d+"
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

var temp_files_dir* = "/mnt/tmpfs".Path
var temp_files: HashSet[string]

proc new_temp_file(name: string): string =
  let path = string temp_files_dir / name.Path
  temp_files.incl path
  return path

proc remove_temp_files() =
  for p in temp_files:
    p.remove_file

add_exit_proc remove_temp_files
set_control_c_hook () {.noconv.} => quit()

type PlaylistKind = enum
  pBandcampAlbum
  pBandcampArtist
  pYoutubePlaylist
  pYoutubeChannel

type Playlist* =
  tuple[
    url: Uri, count: int, id, title, uploader, uploader_id: string, kind: PlaylistKind
  ]

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

  const fields = [
    "playlist_id", "playlist_title", "playlist_count", "playlist_uploader",
    "playlist_uploader_id",
  ]
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
  result.id = d["playlist_id"]
  result.title = d["playlist_title"]
  result.count = parse_int d["playlist_count"]
  result.uploader = d["playlist_uploader"]
  result.uploader_id = d["playlist_uploader_id"]

proc download_page(url: Uri): string =
  let output_lines = exec_process(
    "yt-dlp",
    args = ["--flat-playlist", "--skip-download", "--dump-pages", $(url / "music")],
    options = {po_use_path},
  ).split_lines
  for l in output_lines:
    if is_some l.match page_regex:
      return decode l

iterator items*(playlist: Playlist): Uri =
  if playlist.kind in [pYoutubeChannel, pYoutubeChannel, pBandcampAlbum]:
    let output_lines = exec_process(
      "yt-dlp",
      args = ["--flat-playlist", "--print", "url", $playlist.url],
      options = {po_use_path},
    ).split_lines
    for l in output_lines:
      if l.starts_with "http":
        yield parse_uri l
  elif playlist.kind == pBandcampArtist:
    let page = download_page playlist.url
    var result: OrderedSet[Uri]
    for r in bandcamp_albums_urls_regexes:
      for m in page.find_iter r:
        let c = m.captures[0]
        result.incl block:
          if c.starts_with "http":
            parse_uri c
          else:
            playlist.url / c
    for u in result:
      yield u

type Media* =
  tuple[
    url: Uri, title: string, uploaded: DateTime, uploader: string, thumbnail: string
  ]

func log_string*(m: Media): string =
  &"\"{m.uploader} - {m.title}\""

proc new_media*(url: Uri, client: HttpClient, scale_width: int): Media =
  result.url = url
  let dict = block:
    const fields = ["title", "upload_date", "timestamp", "uploader", "thumbnail"]
    let args = block:
      var r = @["--skip-download"]
      for k in fields:
        r.add "--print"
        r.add k
      r.add $url
      r
    to_table fields.zip exec_process("yt-dlp", args = args, options = {po_use_path}).split_lines
  result.title = dict["title"]
  result.uploader = dict["uploader"]
  result.uploaded = block:
    try:
      utc from_unix parse_int dict["timestamp"]
    except ValueError:
      dict["upload_date"].parse "yyyymmdd", utc()
  result.thumbnail = block:
    let url = dict["thumbnail"]
    let hash = url.XXH3_128bits.to_bytes_b_e.encode(safe = true).replace("=", "")
    let scaled_path = new_temp_file hash & "_scaled.jpg"
    if not scaled_path.file_exists:
      let original = client.get_content url.replace("https", "http")
      let original_path = new_temp_file hash & "_original.jpg"
      open(original_path, fm_write).write original
      let converted_path = new_temp_file hash & "_converted.jpg"
      do_assert (
        &"ffmpeg -y -hide_banner -loglevel error -i {original_path} -f apng {converted_path}"
      ).exec_cmd_ex.exit_code == 0
      do_assert (
        &"ffmpeg -y -hide_banner -loglevel error -i {converted_path} -vf scale={scale_width}:-1 -f apng {scaled_path}"
      ).exec_cmd_ex.exit_code == 0
      original_path.remove_file
      converted_path.remove_file
    scaled_path.read_file

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

proc parse*(url: Uri, client: HttpClient, thumbnail_scale_width: int): Parsed =
  if (($url).match bandcamp_track_url_regex).is_some or
      (($url).match youtube_video_url_regex).is_some:
    return Parsed(kind: pMedia, media: new_media(url, client, thumbnail_scale_width))
  return Parsed(kind: pPlaylist, playlist: new_playlist url)

type Audio* = tuple[data: string, duration: Duration]

func hash(a: Audio): string =
  encode($a.data.XXH3_128bits.to_bytes_b_e, safe = true).replace("=", "")

proc new_audio(data: string): Audio =
  result.data = data
  block duration:
    log(lvl_info, "... duration")
    let output = exec_cmd_ex(
      "ffmpeg -i - -f null - 2>&1 | grep time=", {po_use_path}, input = result.data
    )
    log(lvl_info, "+++ duration")
    do_assert output[1] == 0
    for m in output[0].split_lines[^2].find_iter duration_regex:
      let hours = parse_int m.captures["hours"]
      let minutes = parse_int m.captures["minutes"]
      let seconds = parse_int m.captures["seconds"]
      result.duration = init_duration(seconds = (hours * 60 + minutes) * 60 + seconds)

proc audio(media: Media, format_arg: string): Audio =
  log(lvl_info, &"<-- {media.log_string}")
  let data = exec_process(
    "yt-dlp", args = ["-f", format_arg, "-o", "-", $media.url], options = {po_use_path}
  )
  log(lvl_info, &"+++ {media.log_string}")
  return new_audio data

proc audio*(media: Media): Audio =
  audio media, "mp3"

proc audio*(media: Media, kilobits_per_second: int): Audio =
  let format_arg =
    "ba[abr<=" & $kilobits_per_second & "]/wa[abr>=" & $kilobits_per_second & "]"
  audio media, format_arg

func size*(a: Audio): int =
  a.data.len

proc convert*(
    a: Audio, bitrate: int, samplerate: int = 44100, channels: int = 2
): Audio =
  let temp_file_path = temp_files_dir / encode($a.data.XXH3_128bits, safe = true).Path
  let command =
    "ffmpeg -y -hide_banner -loglevel error -i - -vn -ar " & $samplerate & " -ac " &
    $channels & " -b:a " & $bitrate & " -o " & temp_file_path.string
  let output = exec_cmd_ex(command, {po_use_path}, input = a.data)
  do_assert output[1] == 0
  result = new_audio temp_file_path.string.read_file
  temp_file_path.remove_file

type SplitProcess = tuple[process: Process, output_path: string]

proc start_split_process(
    total_duration: Duration, total_parts: int, part_index: int, input_name: string
): SplitProcess =
  let part_path = new_temp_file input_name & "_" & $(part_index + 1) & ".mp3"
  return (
    process: start_process(
      "ffmpeg",
      args =
        @[
          "-y",
          "-hide_banner",
          "-loglevel",
          "error",
          "-ss",
          $int floor total_duration.in_seconds / total_parts * float part_index,
          "-i",
          new_temp_file input_name,
          "-t",
          $int ceil total_duration.in_seconds / total_parts,
          "-acodec",
          "copy",
          part_path,
        ],
      options = {po_use_path, po_std_err_to_std_out},
    ),
    output_path: part_path,
  )

proc output(p: SplitProcess): Audio =
  do_assert p.process.wait_for_exit == 0
  result = new_audio p.output_path.read_file
  p.process.close
  p.output_path.remove_file

iterator split_into(a: Audio, parts: int): Audio =
  let input_name = a.hash & ".mp3"
  let input_path = new_temp_file input_name
  open(input_path, fm_write).write a.data
  var processes: seq[SplitProcess]
  for i in 0 .. (parts - 1):
    processes.add start_split_process(a.duration, parts, i, input_name)
  for p in processes:
    yield p.output
  input_path.string.remove_file

iterator split*(a: Audio, part_size: int): Audio =
  for r in a.split_into int ceil a.size / part_size:
    yield r
