import std/[options, sequtils, strformat, os, logging, sugar, paths]

import tempfiles
import commands

type ConversionParams* = object
  bitrate*: int
  samplerate*: int
  channels*: int

type Downloader* = object
  bitrate*: Option[int]
  conversion_params*: Option[ConversionParams]
  thumbnail_scale_width*: int

proc download_audio*(downloader: Downloader, url: string, name: string): string =
  let original_path = name.new_temp_file
  discard new_temp_file string name.Path.add_file_ext "part"
  block download:
    let format =
      if is_some downloader.bitrate:
        &"ba[abr<={downloader.bitrate.get}]/wa[abr>={downloader.bitrate.get}]"
      else:
        "mp3"
    lvl_info.log &"<-- {url}"
    discard "yt-dlp".execute @["-f", format, "-o", original_path, url]

  if is_some downloader.conversion_params:
    let converted_path = (&"{name}.mp3").new_temp_file
    discard "ffmpeg".execute @[
      "-i",
      original_path,
      "-vn",
      "-ar",
      $downloader.conversion_params.get.samplerate,
      "-ac",
      $downloader.conversion_params.get.channels,
      "-b:a",
      $downloader.conversion_params.get.bitrate,
      converted_path,
    ]
    original_path.remove_file
    return converted_path
  else:
    return original_path

proc download_thumbnail*(downloader: Downloader, url: string, name: string): string =
  let scaled_path = (&"{name}.png").new_temp_file
  if scaled_path.file_exists:
    return scaled_path
  let original_path = block:
    let original_name = &"{name}_o"
    let possible_original_paths =
      ["jpg", "webp"].map (e: string) => (&"{original_name}.{e}").new_temp_file
    discard "yt-dlp".execute @[
      url, "--write-thumbnail", "--skip-download", "-o", original_name.new_temp_file
    ]
    possible_original_paths.filter(file_exists)[0]
  let converted_path = (&"{name}_c.png").new_temp_file
  discard "ffmpeg".execute @["-i", original_path, converted_path]
  discard "ffmpeg".execute @[
    "-i",
    converted_path,
    "-vf",
    &"scale={downloader.thumbnail_scale_width}:-1",
    scaled_path,
  ]
  original_path.remove_file
  converted_path.remove_file
  scaled_path
