import
  std/[
    uri, os, enumerate, httpclient, logging, strformat, options, strutils, paths, math,
    sugar,
  ]

import common
import tempfiles
import commands

const max_uploaded_audio_size = 1024 * 1024 * 48

var default_http_client* = new_http_client()

type Uploader* = object
  token: string

iterator split(
    audio_path: string, total_duration: int
): tuple[path: string, duration: int] =
  let parts = int ceil audio_path.get_file_size / max_uploaded_audio_size
  let part_duration = int ceil total_duration / parts
  let processes = collect:
    for i in 0 .. (parts - 1):
      let part_path = (&"{audio_path.Path.split_file.name.string}_{i + 1}").new_temp_file.add_file_ext "mp3"
      (
        process: "ffmpeg".new_command_process @[
          "-y",
          "-hide_banner",
          "-loglevel",
          "error",
          "-ss",
          $int floor total_duration / parts * float i,
          "-i",
          audio_path,
          "-t",
          $part_duration,
          "-acodec",
          "copy",
          part_path,
        ],
        path: part_path,
      )
  for p in processes:
    discard p.process.wait_for_exit
    assert p.path.get_file_size <= max_uploaded_audio_size
    yield (path: p.path, duration: part_duration)
  audio_path.remove_file

proc upload*(uploader: Uploader, item: Item, downloaded: Downloaded, chat_id: string) =
  if downloaded.audio_path.get_file_size >= max_uploaded_audio_size:
    for i, part in enumerate downloaded.audio_path.split item.duration:
      var part_item = item
      part_item.title = &"{item.title} - {i + 1}"
      part_item.duration = part.duration
      uploader.upload(
        part_item,
        Downloaded(audio_path: part.path, thumbnail_path: downloaded.thumbnail_path),
        chat_id,
      )
    return

  var multipart = new_multipart_data()
  multipart.add_files {
    "audio": downloaded.audio_path, "thumbnail": downloaded.thumbnail_path
  }
  multipart["chat_id"] = chat_id
  if is_some item.performer:
    multipart["performer"] = item.performer.get
  multipart["title"] = item.title
  multipart["duration"] = $item.duration
  multipart["disable_notification"] = "true"

  let log_string =
    if is_some item.performer:
      &"{item.performer.get} - {item.title}"
    else:
      item.title
  log(lvl_info, &"--> {log_string}")

  while true:
    var response: Response
    while true:
      try:
        response = default_http_client.request(
          "https://api.telegram.org/bot" & uploader.token & "/sendAudio",
          http_method = HttpPost,
          multipart = multipart,
        )
        break
      except:
        continue
    if not response.status.starts_with "200":
      lvl_warn.log &"response is {response.status} {response.body}"
      if response.status.starts_with "429":
        sleep(1000)
      continue
    break
  downloaded.audio_path.remove_file
