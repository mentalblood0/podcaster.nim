import argparse

import std/uri
import std/sugar
import std/httpclient

import telegram
import ytdlp

proc upload(bot: Bot, url: Uri) =
  let parsed = parse url
  if parsed.kind == pPlaylist:
    for url in parsed.playlist:
      bot.upload url
  elif parsed.kind == pMedia:
    bot.upload parsed.media

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
      "-t",
      "--temp_files_dir",
      "Where to write temporary files directory",
      default = some("/mnt/tmpfs"),
      required = false,
    )
    arg("url")
    run:
      let bot = new_bot(
        chat_id: opts.chat_id,
        token: opts.token,
        client: block:
          if is_some opts.proxy:
            new_http_client(proxy = new_proxy opts.proxy.get)
          else:
            new_http_client(),
        bitrate: int opts.bitrate,
      )
      bot.upload parse_uri opts.url

parser.run
