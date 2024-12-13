import std/os
import std/times
import std/options
import std/strutils
import std/httpclient

import ytdlp

var telegram_http_client* = new_http_client()

type Bot* = tuple[chat_id: int, token: string, bitrate: int, max_part_size: int]

proc new_bot*(
    chat_id: int,
    token: string,
    bitrate: int = 128,
    max_part_size: int = 1024 * 1024 * 48,
): Bot =
  (chat_id, token, bitrate, max_part_size)

proc upload(b: Bot, a: Audio, title: string, thumbnail_path: string) =
  var multipart = new_multipart_data()
  multipart.add_files {"audio": a.path, "thumbnail": thumbnail_path}
  multipart["chat_id"] = $b.chat_id
  let performer_and_title = title.split("-", 2)
  multipart["performer"] = performer_and_title[0].strip
  multipart["title"] = performer_and_title[1].strip
  multipart["duration"] = $a.duration.in_seconds

  discard telegram_http_client.post_content(
    "https://api.telegram.org/bot" & b.token & "/sendAudio", multipart = multipart
  )
  a.path.remove_file

proc upload*(b: Bot, m: Media) =
  let a = m.audio some(b.bitrate)

  if a.path.get_file_size >= b.max_part_size:
    for a_part in a.split b.max_part_size:
      b.upload(a_part, m.title, m.thumbnail_path)
  else:
    b.upload(a, m.title, m.thumbnail_path)
