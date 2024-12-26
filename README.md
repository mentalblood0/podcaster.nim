## podcaster.nim

Fast and stable Bandcamp/Youtube to Telegram audio uploader

### Dependencies

`yt-dlp` and `ffmpeg`

Also use tmpfs or analogous filesystem for temporary files storage to reduce your HDD/SSD wear and tear

### Build

```Bash
nim c -d:ssl -d:release podcaster.nim
```

### Usage

```bash
podcaster --help
```

### Configuration

Configuration file `~/.config/podcaster/bandcamp_music.json`:

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

Configuration file `~/.config/podcaster/youtube_music.json`:

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

### Restoring uploaded items identifiers

Use `start_after_url` task key. It should be album URL for Bandcamp and video URL for Youtube
