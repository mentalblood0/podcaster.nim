# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import std/os
import std/nre
import std/times
import std/options
import std/strutils
import std/strformat
import std/httpclient
import std/logging

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
  multipart["title"] = title
  multipart["duration"] = $a.duration.in_seconds

  log(lvl_info, &"--> {title}")
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
