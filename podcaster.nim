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
      "-c",
      "--chat_id",
      "Telegram chat id, you can forward message from chat to @getidsbot to get chat's id",
      required = true,
    )
    option(
      "-t",
      "--token",
      "Telegram bot token, use @BotFather to create bot and get it's token",
      required = true,
    )
    option(
      "-C",
      "--cache",
      "Path to cache file used to not retrieve and upload media repeatedly",
      required = true,
    )
    option(
      "-p",
      "--proxy",
      "Address of HTTP proxy to use",
      env = "http_proxy",
      required = false,
    )
    option(
      "-b",
      "--bitrate",
      "Preferable audio bitrate",
      default = some("128"),
      required = false,
    )
    option(
      "-d",
      "--temp_files_dir",
      "Where to write temporary files. Mount and use tmpfs to minimize hard drive wear",
      required = true,
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
      var cache = new_cache opts.cache

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

      let bot = new_bot(
        chat_id = parse_int opts.chat_id,
        token = opts.token,
        bitrate = parse_int opts.bitrate,
      )
      bot.upload parse_uri opts.url

parser.run
