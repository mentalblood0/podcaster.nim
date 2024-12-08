import ytdlp
import std/options
import std/sugar
import std/times
import std/httpclient

type Bot* = tuple[chat_id, token: string, client: HttpClient]

proc upload(
    b: Bot,
    a: Audio,
    title: string,
    performer: string,
    thumbnail: Thumbnail,
    max_part_size: int = 1024 * 1024 * 48,
) =
  dump a.duration

  var multipart = new_multipart_data()
  multipart["audio"] = (title & ".mp3", "audio/mpeg", a.data)
  multipart["thumbnail"] = ("cover.jpeg", "image/jpeg", thumbnail.string)
  multipart["chat_id"] = b.chat_id
  multipart["title"] = title
  multipart["performer"] = performer
  multipart["duration"] = $a.duration.in_seconds

  discard b.client.post_content(
    "https://api.telegram.org/bot" & b.token & "/sendAudio", multipart = multipart
  )

proc upload*(b: Bot, m: Media, max_part_size: int = 1024 * 1024 * 48) =
  let a = m.audio 128
  dump a.duration

  let thumbnail = m.thumbnail(none(int), b.client)

  if a.size >= max_part_size:
    for a_part in a.crop_by_size max_part_size:
      b.upload(a_part, m.title, m.uploader.get, thumbnail, max_part_size)
  else:
    b.upload(m.audio, m.title, m.uploader.get, thumbnail, max_part_size)
