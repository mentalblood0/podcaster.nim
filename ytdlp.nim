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

var temp_files_dir = "/mnt/tmpfs".Path

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

type SplitProcess = tuple[process: Process, output_path: Path]

proc start_split_process(
    total_duration: Duration, total_parts: int, part_index: int, input_name: string
): SplitProcess =
  let part_name = input_name & "_" & $(part_index + 1) & ".mp3"
  return (
    process: start_process(
      "ffmpeg",
      temp_files_dir.string,
      @[
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        $int floor total_duration.in_seconds / total_parts * float part_index,
        "-i",
        input_name,
        "-t",
        $int ceil total_duration.in_seconds / total_parts,
        "-acodec",
        "copy",
        part_name,
      ],
      options = {po_use_path, po_std_err_to_std_out},
    ),
    output_path: temp_files_dir / part_name.Path,
  )

proc output(p: SplitProcess): Audio =
  do_assert p.process.wait_for_exit == 0
  result = new_audio p.output_path.string.read_file
  p.output_path.remove_file

iterator split_into(a: Audio, parts: int): Audio =
  let input_name = encode($a.data.XXH3_128bits, safe = true) & ".mp3"
  let input_path = temp_files_dir / input_name.Path
  open(input_path.string, fm_write).write a.data
  var processes: seq[SplitProcess]
  for i in 0 .. (parts - 1):
    processes.add start_split_process(a.duration, parts, i, input_name)
  for p in processes:
    yield p.output
  input_path.string.remove_file

iterator split*(a: Audio, part_size: int): Audio =
  for r in a.split_into int ceil a.size / part_size:
    yield r
