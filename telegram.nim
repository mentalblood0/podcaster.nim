import std/os
import std/times
import std/options
import std/strutils
import std/strformat
import std/httpclient
import std/logging

import ytdlp

type Bot* =
  tuple[
    token: string, download_bitrate: int, conversion_params: Option[ConversionParams]
  ]
