import std/os
import std/appdirs
import std/options
import std/times
import std/options
import std/strutils
import std/strformat
import std/httpclient
import std/logging

import ytdlp

const max_uploaded_audio_size = 1024 * 1024 * 48

var telegram_http_client* = new_http_client()

type Bot* =
  tuple[
    chat_id: int,
    token: string,
    download_bitrate: int,
    conversion_params: Option[ConversionParams],
  ]

proc upload(b: Bot, a: Audio, title: string, thumbnail_path: string) =
  var multipart = new_multipart_data()
  multipart.add_files {"audio": a.path, "thumbnail": thumbnail_path}
  multipart["chat_id"] = $b.chat_id
  multipart["title"] = title
  multipart["duration"] = $a.duration.in_seconds

  log(lvl_info, &"--> {title}")
  discard telegram_http_client.post_content(
    "https://api.telegram.org/bot" & b.token & "/sendAudio", multipart = multipart
  )
  a.path.remove_file

proc upload*(b: Bot, m: Media) =
  let a = block:
    if is_some b.conversion_params:
      (m.audio some b.download_bitrate).convert b.conversion_params.get
    else:
      m.audio some b.download_bitrate

  if a.path.get_file_size >= max_uploaded_audio_size:
    for a_part in a.split max_uploaded_audio_size:
      b.upload(a_part, m.title, m.thumbnail_path)
  else:
    b.upload(a, m.title, m.thumbnail_path)
