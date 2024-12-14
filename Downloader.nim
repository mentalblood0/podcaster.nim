import std/options

import ytdlp

type Downloader* =
  tuple[
    bitrate: Option[int],
    conversion_params: Option[ConversionParams],
    thumbnail_scale_width: int,
  ]

proc download*(d: Downloader, m: Media): Audio =
  if is_some d.conversion_params:
    return (m.audio d.bitrate).convert d.conversion_params.get
  else:
    return m.audio d.bitrate

proc download_thumbnail*(d: Downloader, m: Media) =
  m.download_thumbnail d.thumbnail_scale_width
