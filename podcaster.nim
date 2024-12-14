import argparse

import std/uri
import std/httpclient
import std/logging
import std/paths
import std/strformat

import telegram
import ytdlp
import cache

var parser = new_parser:
  command "upload":
    option(
      "-ch",
      "--chat_id",
      "Telegram chat id, you can forward message from chat to @getidsbot to get chat's id",
      required = true,
    )
    option(
      "-t",
      "--token",
      "Telegram bot token, use @BotFather to create bot and get it's token",
      env = "podcaster_token",
      required = false,
    )
    option(
      "-p",
      "--proxy",
      "Address of HTTP proxy to use",
      env = "podcaster_http_proxy",
      required = false,
    )
    option(
      "-b",
      "--bitrate",
      "Preferable downloaded audio bitrate",
      default = some("128"),
      required = false,
    )
    option(
      "-co",
      "--convert",
      "Conversion of downloaded audio according to given bitrate:samplerate:channels",
      required = false,
    )
    option(
      "-d",
      "--temp_files_dir",
      "Where to write temporary files. Mount and use tmpfs to minimize hard drive wear",
      env = "podcaster_temp_dir",
      required = false,
    )
    option(
      "-l",
      "--log_level",
      "Level messages below which will not be outputed",
      choices = @["debug", "info", "error"],
      default = some("info"),
      required = false,
    )
    arg("url")
    run:
      let url_arg = parse_uri opts.url
      var cache = new_cache url_arg

      proc upload(bot: Bot, url: Uri) =
        let is_bandcamp = is_bandcamp_url url
        if is_bandcamp and (url in cache):
          return
        log(lvl_info, &"<-- {url}")
        let parsed = parse(url, 200)
        if parsed.kind == pPlaylist:
          for url in parsed.playlist:
            if is_bandcamp and url notin cache:
              bot.upload url
              cache.incl url
            else:
              bot.upload url
          if is_bandcamp:
            cache.incl url
        elif parsed.kind == pMedia and parsed.media notin cache:
          bot.upload parsed.media
          if is_bandcamp:
            cache.incl url
          else:
            cache.incl parsed.media

      ytdlp_proxy = opts.proxy

      case opts.log_level
      of "debug":
        set_log_filter lvl_debug
      of "info":
        set_log_filter lvl_info
      of "error":
        set_log_filter lvl_error

      let bot = (
        chat_id: parse_int opts.chat_id,
        token: opts.token,
        download_bitrate: parse_int opts.bitrate,
        conversion_params:
          if opts.convert.len > 0:
            let splitted = opts.convert.split(':').map parse_int
            some (bitrate: splitted[0], samplerate: splitted[1], channels: splitted[2])
          else:
            none(ConversionParams),
      )
      bot.upload url_arg

parser.run
