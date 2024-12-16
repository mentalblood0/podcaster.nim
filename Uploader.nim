import
  std/[uri, os, times, enumerate, httpclient, logging, strformat, options, strutils]

import ytdlp

const max_uploaded_audio_size = 1024 * 1024 * 48

var default_http_client* = new_http_client()

type Uploader* = tuple[token: string, chat_id: string]

proc upload*(
    uploader: Uploader,
    a: Audio,
    performer: Option[string],
    title: string,
    thumbnail_path: string,
) =
  if a.path.get_file_size >= max_uploaded_audio_size:
    for i, a_part in enumerate a.split max_uploaded_audio_size:
      uploader.upload(a_part, performer, &"{title} - {i + 1}", thumbnail_path)
    return

  var multipart = new_multipart_data()
  multipart.add_files {"audio": a.path, "thumbnail": thumbnail_path}
  multipart["chat_id"] = uploader.chat_id
  if is_some performer:
    multipart["performer"] = performer.get
  multipart["title"] = title
  multipart["duration"] = $a.duration.in_seconds
  multipart["disable_notification"] = "true"

  log(lvl_debug, &"multipart is:\n{multipart}")

  log(lvl_info, &"--> {log_string(performer, title)}")
  while true:
    let response = default_http_client.request(
      "https://api.telegram.org/bot" & uploader.token & "/sendAudio",
      http_method = HttpPost,
      multipart = multipart,
    )
    log(lvl_debug, &"response is {response.status} {response.body}")
    if response.status.starts_with "429":
      sleep(1000)
      continue
    do_assert response.status == "200 OK"
    break
  a.path.remove_file
