# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import std/base64
import std/os
import std/sugar
import std/math
import std/httpclient
import std/files
import std/paths
import std/options
import std/times
import std/nre
import std/sets
import std/tables
import std/sequtils
import std/strutils
import std/osproc
import std/uri

import xxhash

let page_regex = re"[^\[].*"
let bandcamp_albums_urls_regexes =
  @[
    re("href=\"([^&\\n]+)&amp;tab=music"),
    re("\"(\\/(?:album|track)\\/[^\"]+)\""),
    re(";(\\/(?:album|track)\\/[^&\"]+)(?:&|\")"),
    re"page_url&quot;:&quot;([^&]+)&",
  ]
let duration_regex = re"time=(?P<hours>\d+):(?P<minutes>\d+):(?P<seconds>\d+)\.\d+"

type Playlist* = tuple[url: Uri, id, title, count, uploader, uploader_id: string]

proc playlist*(url: Uri): Playlist =
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
  return (
    url: url,
    id: d["playlist_id"],
    title: d["playlist_title"],
    count: d["playlist_count"],
    uploader: d["playlist_uploader"],
    uploader_id: d["playlist_uploader_id"],
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

proc get_bandcamp_albums_urls*(url: Uri): OrderedSet[Uri] =
  let page = download_page url
  for r in bandcamp_albums_urls_regexes:
    for m in page.find_iter r:
      let c = m.captures[0]
      result.incl block:
        if c.starts_with "http":
          parse_uri c
        else:
          url / c

iterator items*(playlist: Playlist): Uri =
  let output_lines = exec_process(
    "yt-dlp",
    args = ["--flat-playlist", "--print", "url", $playlist.url],
    options = {po_use_path},
  ).split_lines
  for l in output_lines:
    if l.starts_with "http":
      yield parse_uri l

type Media* =
  tuple[
    url: Uri,
    title: string,
    uploaded: DateTime,
    uploader: Option[string],
    thumbnail_url: Uri,
  ]

proc media*(url: Uri): Media =
  const fields = ["title", "upload_date", "timestamp", "uploader", "thumbnail"]
  let args = block:
    var r = @["--skip-download"]
    for k in fields:
      r.add "--print"
      r.add k
    r.add $url
    r
  let d = to_table fields.zip exec_process(
    "yt-dlp", args = args, options = {po_use_path}
  ).split_lines
  return (
    url: url,
    title: d["title"],
    uploaded: block:
      try:
        utc from_unix parse_int d["timestamp"]
      except ValueError:
        d["upload_date"].parse "yyyymmdd", utc()
    ,
    uploader: block:
      if "uploader" in d:
        some(d["uploader"])
      else:
        none(string),
    thumbnail_url: parse_uri d["thumbnail"],
  )

type Thumbnail* = distinct string

proc thumbnail*(m: Media, scale_width: Option[int], client: HttpClient): Thumbnail =
  let fullsize = client.get_content ($m.thumbnail_url).replace("https", "http")
  if not is_some scale_width:
    return fullsize.Thumbnail
  let png = block:
    let output = exec_cmd_ex("ffmpeg -i - -f apng -", {po_use_path}, input = fullsize)
    do_assert output[1] == 0
    output[0]
  let scaled = block:
    let output = exec_cmd_ex(
      "ffmpeg -y -hide_banner -loglevel error -i - -vf scale=150:-1 -f apng -",
      {po_use_path},
      input = png,
    )
    do_assert output[1] == 0
    output[0]
  return scaled.Thumbnail

type Audio* = tuple[data: string, duration: Duration]

proc new_audio(data: string): Audio =
  result.data = data
  block duration:
    let output = exec_cmd_ex(
      "ffmpeg -i - -f null - 2>&1 | grep time=", {po_use_path}, input = result.data
    )
    do_assert output[1] == 0
    for m in output[0].split_lines[^2].find_iter duration_regex:
      let hours = parse_int m.captures["hours"]
      let minutes = parse_int m.captures["minutes"]
      let seconds = parse_int m.captures["seconds"]
      result.duration = init_duration(seconds = (hours * 60 + minutes) * 60 + seconds)

proc audio(media: Media, format_arg: string): Audio =
  new_audio exec_process(
    "yt-dlp", args = ["-f", format_arg, "-o", "-", $media.url], options = {po_use_path}
  )

proc audio*(media: Media): Audio =
  audio media, "mp3"

proc audio*(media: Media, kilobits_per_second: int): Audio =
  let format_arg =
    "ba[abr<=" & $kilobits_per_second & "]/wa[abr>=" & $kilobits_per_second & "]"
  audio media, format_arg

func size*(a: Audio): int =
  a.data.len

proc convert*(
    a: Audio,
    bitrate: int,
    temp_files_dir: Path = "/mnt/tmpfs".Path,
    samplerate: int = 44100,
    channels: int = 2,
): Audio =
  let temp_file_path = temp_files_dir / encode($a.data.XXH3_128bits, safe = true).Path
  let command =
    "ffmpeg -y -hide_banner -loglevel error -i - -vn -ar " & $samplerate & " -ac " &
    $channels & " -b:a " & $bitrate & " -o " & temp_file_path.string
  let output = exec_cmd_ex(command, {po_use_path}, input = a.data)
  do_assert output[1] == 0
  result = new_audio temp_file_path.string.read_file
  temp_file_path.remove_file

iterator split_into(a: Audio, parts: int, temp_files_dir: Path): Audio =
  let part_seconds = int ceil a.duration.in_seconds / parts
  let temp_file_path = temp_files_dir / encode($a.data.XXH3_128bits, safe = true).Path
  open(temp_file_path.string, fm_write).write a.data
  for i in 0 .. (parts - 1):
    let start = int floor a.duration.in_seconds / parts * float i
    let part_temp_file_path = temp_file_path.string & "_" & $(i + 1) & ".mp3"
    let command =
      "ffmpeg -y -hide_banner -loglevel error -ss " & $start & " -i " &
      temp_file_path.string & " -t " & $part_seconds & " -acodec copy " &
      part_temp_file_path & " 2>&1"
    dump command
    let output = exec_cmd_ex(command, {po_use_path})
    if output[1] != 0:
      dump output[0]
    do_assert output[1] == 0
    let r = new_audio part_temp_file_path.string.read_file
    part_temp_file_path.remove_file
    yield r
  temp_file_path.remove_file

iterator split_by_size*(
    a: Audio, part_size: int, temp_files_dir: Path = "/mnt/tmpfs".Path
): Audio =
  for r in a.split((a.size / part_size).ceil.int, temp_files_dir):
    yield r
