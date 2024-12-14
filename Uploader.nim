import std/[uri, os, times, enumerate, httpclient, logging, strformat]

import ytdlp

const max_uploaded_audio_size = 1024 * 1024 * 48

var default_http_client* = new_http_client()

type Uploader* = tuple[token: string, chat_id: string]

proc upload*(uploader: Uploader, a: Audio, title: string, thumbnail_path: string) =
  if a.path.get_file_size >= max_uploaded_audio_size:
    for i, a_part in enumerate a.split max_uploaded_audio_size:
      uploader.upload(a_part, &"{title} - {i + 1}", thumbnail_path)
    return

  var multipart = new_multipart_data()
  multipart.add_files {"audio": a.path, "thumbnail": thumbnail_path}
  multipart["chat_id"] = uploader.chat_id
  multipart["title"] = title
  multipart["duration"] = $a.duration.in_seconds

  log(lvl_debug, &"multipart is:\n{multipart}")

  log(lvl_info, &"--> {title}")
  let response = default_http_client.request(
    "https://api.telegram.org/bot" & uploader.token & "/sendAudio",
    http_method = HttpPost,
    multipart = multipart,
  )
  log(lvl_debug, &"response is {response.status} {response.body}")
  a.path.remove_file
  do_assert response.status == "200 OK"
