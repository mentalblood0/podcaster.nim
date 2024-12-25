## podcaster.nim

Fast and stable bandcamp/youtube to telegram audio uploader

### Build

```Bash
nim c -d:ssl -d:release podcaster.nim
```

### Example

Config at `~/.config/podcaster/bandcamp_music.json`:

```Json
{
  "ytdlp_proxy": "http://127.0.0.1:2080",
  "temp_files_dir": "/mnt/tmpfs",
  "log_level": "info",
  "podcaster": {
    "downloader": {
      "bitrate": 128,
      "thumbnail_scale_size": 200
    },
    "uploader": {
      "token": "insert your telegram bot token here"
    }
  },
  "tasks": [
    {
      "chat_id": "-1002233871690",
      "url": "https://lofigirl.bandcamp.com"
    },
    {
      "chat_id": "-1002160479843",
      "url": "https://monstercatmedia.bandcamp.com"
    },
  ]
}
```

Config at `~/.config/podcaster/youtube_music.json`:

```Json
{
  "ytdlp_proxy": "http://127.0.0.1:2080",
  "temp_files_dir": "/mnt/tmpfs",
  "log_level": "info",
  "podcaster": {
    "downloader": {
      "bitrate": 192,
      "conversion_params": {
        "bitrate": 128,
        "samplerate": 44100,
        "channels": 2
      },
      "thumbnail_scale_size": 200
    },
    "uploader": {
      "token": "insert your telegram bot token here"
    }
  },
  "tasks": [
    {
      "chat_id": "-1002220980330",
      "url": "https://www.youtube.com/@untitledburial/videos",
      "performer_from_title": true
    },
    {
      "chat_id": "-1002184412681",
      "url": "https://www.youtube.com/@OBSIDIANSOUNDFIELDS/videos"
    },
    {
      "chat_id": "-1002226329150",
      "url": "https://www.youtube.com/@EternalDystopiaMusic/videos"
    },
  ]
}
```

Launch:

```Bash
podcaster bandcamp_music youtube_music
```
