import std/[options, logging, json, appdirs, paths, cmdline, strutils, strformat]

import downloader
import uploader
import common
import tempfiles
import commands

import youtube
import bandcamp

type Task = object
  chat_id: string
  url: string
  start_after_url: Option[string]

type Podcaster = object
  downloader: Downloader
  uploader: Uploader

type Config = object
  ytdlp_proxy: string
  temp_files_dir: string
  log_level: string
  podcaster: Podcaster
  tasks: seq[Task]

template process_task(podcaster: typed, task: typed, T: untyped) =
  var collector = new_items_collector task.url.T
  lvl_debug.log "process task " & $task

  if task.start_after_url.is_some:
    collector.cache_until_including task.start_after_url.get

  for item in collector:
    lvl_debug.log "process item " & $item

    var downloaded: Downloaded
    try:
      downloaded = Downloaded(
        audio_path: podcaster.downloader.download_audio item.url,
        thumbnail_path:
          podcaster.downloader.download_thumbnail(item.url, item.thumbnail_id),
      )
    except CommandFatalError:
      collector.on_uploaded item
      continue

    podcaster.uploader.upload(item, downloaded, task.chat_id)
    collector.on_uploaded(item, some(downloaded))

when is_main_module:
  let config = (
    parse_json read_file string get_config_dir() / "podcaster".Path / Path param_str 1
  ).to Config

  ytdlp_proxy = config.ytdlp_proxy
  temp_files_dir = config.temp_files_dir

  add_handler new_console_logger(fmt_str = "$date $time $levelname ")
  case config.log_level
  of "debug":
    set_log_filter lvl_debug
  of "info":
    set_log_filter lvl_info
  of "error":
    set_log_filter lvl_error

  for t in config.tasks:
    try:
      try:
        config.podcaster.process_task(t, BandcampUrl)
        continue
      except UnsupportedUrlError:
        discard
      try:
        config.podcaster.process_task(t, YoutubeUrl)
        continue
      except UnsupportedUrlError:
        discard
      raise new_exception(UnsupportedUrlError, &"No module support URL '{t.url}'")
    except:
      remove_temp_files()
      raise
