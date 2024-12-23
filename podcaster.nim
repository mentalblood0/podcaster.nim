# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import std/[options, logging, json, cmdline, strutils, strformat, nre, os]

import downloader
import uploader
import common
import tempfiles
import commands
import cache

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

type ClassifiedTask[T] = object
  source: Task

proc new_items_collector*[T](u: T): ItemsCollector[T] =
  result.url = u
  result.cache = new_cache (u.string.match url_regex u).get.captures[0]

proc on_uploaded*[T](
    items_collector: var ItemsCollector[T],
    item: Item,
    downloaded: Option[Downloaded] = none(Downloaded),
) =
  for c in item.cache_items:
    items_collector.cache.incl c
  if downloaded.is_some and not item.keep_thumbnail:
    downloaded.get.thumbnail_path.remove_temp_file

proc process_task[T](podcaster: Podcaster, task: ClassifiedTask[T]) =
  var collector = new_items_collector task.source.url.T
  lvl_debug.log "process task " & $task

  if task.source.start_after_url.is_some:
    collector.cache_until_including task.source.start_after_url.get

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

    podcaster.uploader.upload(item, downloaded, task.source.chat_id)
    collector.on_uploaded(item, some(downloaded))

when is_main_module:
  let config =
    (parse_json read_file get_config_dir() / "podcaster" / param_str 1).to Config

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
      if is_some t.url.match t.url.BandcampUrl.url_regex:
        config.podcaster.process_task ClassifiedTask[BandcampUrl](source: t)
      elif is_some t.url.match t.url.YoutubeUrl.url_regex:
        config.podcaster.process_task ClassifiedTask[YoutubeUrl](source: t)
      else:
        raise new_exception(UnsupportedUrlError, &"No module support url '{t.url}'")
    except:
      remove_temp_files()
      raise
