import std/times
import std/times
import std/options
import std/httpclient

import ytdlp

type Bot* =
  tuple[
    chat_id: int, token: string, client: HttpClient, bitrate: int, max_part_size: int
  ]

proc new_bot*(
    chat_id: int,
    token: string,
    client: HttpClient = new_http_client(),
    bitrate: int = 128,
    max_part_size: int = 1024 * 1024 * 48,
): Bot =
  (chat_id, token, client, bitrate, max_part_size)

proc upload(
    b: Bot, a: Audio, title: string, performer: string, thumbnail_path: string
) =
  var multipart = new_multipart_data()
  multipart.add_files {"audio": a.path, "thumbnail": thumbnail_path}
  multipart["chat_id"] = $b.chat_id
  multipart["title"] = title
  multipart["performer"] = performer
  multipart["duration"] = $a.duration.in_seconds

  discard b.client.post_content(
    "https://api.telegram.org/bot" & b.token & "/sendAudio", multipart = multipart
  )

proc upload*(b: Bot, m: Media) =
  let a = m.audio some(b.bitrate)

  if a.size >= b.max_part_size:
    for a_part in a.split b.max_part_size:
      b.upload(a_part, m.title, m.uploader, m.thumbnail_path)
  else:
    b.upload(a, m.title, m.uploader, m.thumbnail_path)
