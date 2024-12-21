import std/[options, logging, json, appdirs, paths, cmdline, strutils, strformat]

import downloader
import uploader
import common
import tempfiles
import logging
import commands

import youtube

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

proc process_task(podcaster: Podcaster, task: Task) =
  var skip = task.start_after_url.is_some
  for item in task.url.YoutubeUrl.items:
    if skip:
      if task.start_after_url.get == item.url:
        skip = false
      continue
    lvl_info.log &"process item {item}"
    var downloaded: Downloaded
    try:
      downloaded = Downloaded(
        audio_path: podcaster.downloader.download_audio(item.url, item.name),
        thumbnail_path: podcaster.downloader.download_thumbnail(item.url, item.name),
      )
    except CommandFatalError:
      continue
    podcaster.uploader.upload(item, downloaded, task.chat_id)

when is_main_module:
  let config = (
    parse_json read_file string get_config_dir() / "podcaster".Path / Path param_str 1
  ).to Config

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
      config.podcaster.process_task t
    except:
      remove_temp_files()
      raise
