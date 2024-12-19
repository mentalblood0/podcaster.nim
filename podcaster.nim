import std/[options, logging, marshal, appdirs, paths, cmdline, hashes]

import downloader
import uploader
import common
import tempfiles
import logging

import youtube

type Task = object
  chat_id: string
  url: string

type Podcaster = object
  downloader: Downloader
  uploader: Uploader

type Config = object
  ytdlp_proxy: string
  temp_files_dir: string
  log_level: string
  podcaster: Podcaster
  tasks: seq[Task]

proc upload(podcaster: Podcaster, url: string, chat_id: string) =
  for item in url.YoutubeUrl.items:
    let downloaded = Downloaded(
      audio_path: podcaster.downloader.download_audio(item.url, $item.hash),
      thumbnail_path: podcaster.downloader.download_thumbnail(item.url, $item.hash),
    )
    podcaster.uploader.upload(item, downloaded, chat_id)

when is_main_module:
  let config =
    to[Config] read_file string get_config_dir() / "podcaster".Path / Path param_str 1

  ytdlp_proxy = config.ytdlp_proxy
  temp_files_dir = config.temp_files_dir

  case config.log_level
  of "debug":
    set_log_filter lvl_debug
  of "info":
    set_log_filter lvl_info
  of "error":
    set_log_filter lvl_error

  for t in config.tasks:
    try:
      config.podcaster.upload(t.url, t.chat_id)
    except:
      remove_temp_files()
      raise
