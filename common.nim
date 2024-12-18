type
  Item* = object
    audio_path*: string
    thumbnail_path*: string
    performer*: string
    title*: string
    duration*: int

  UnsupportedUrlError* = object of ValueError

var ytdlp_proxy* = ""
