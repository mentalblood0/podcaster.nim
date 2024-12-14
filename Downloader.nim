import std/options

import ytdlp

type Downloader* =
  tuple[bitrate: Option[int], conversion_params: Option[ConversionParams]]

proc download*(d: Downloader, m: Media): Audio =
  if is_some d.conversion_params:
    return (m.audio d.bitrate).convert d.conversion_params.get
  else:
    return m.audio d.bitrate
