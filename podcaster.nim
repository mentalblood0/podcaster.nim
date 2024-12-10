import argparse

import std/uri
import std/httpclient
import std/logging
import std/strformat

import telegram
import ytdlp

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
    arg("url")
    run:
      proc upload(bot: Bot, url: Uri) =
        log(lvl_info, &"<-> {url}")
        let parsed = parse(url, bot.client, 150)
        if parsed.kind == pPlaylist:
          for url in parsed.playlist:
            bot.upload url
        elif parsed.kind == pMedia:
          bot.upload parsed.media
        log(lvl_info, &"+++ {url}")

      let bot = new_bot(
        chat_id = parse_int opts.chat_id,
        token = opts.token,
        client = block:
          if opts.proxy.len > 0:
            new_http_client(proxy = new_proxy opts.proxy)
          else:
            new_http_client(),
        bitrate = parse_int opts.bitrate,
      )
      bot.upload parse_uri opts.url

parser.run
