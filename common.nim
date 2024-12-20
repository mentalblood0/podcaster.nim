import std/[options, strutils, sugar, sequtils, hashes]

type
  Item* = object
    url*: string
    performer*: Option[string]
    title*: string
    duration*: int

  Downloaded* = object
    audio_path*: string
    thumbnail_path*: string

  UnsupportedUrlError* = object of ValueError

var ytdlp_proxy* = ""

func name*(item: Item): string =
  ($item.hash).strip(trailing = false, chars = {'-'})

func decouple_performer_and_title*(
    performer: string, title: string
): tuple[performer: Option[string], title: string] =
  if performer in ["", "NA"]:
    let splitted = title.split("-", 1).map (s: string) => s.strip
    if splitted.len == 1:
      return (performer: none(string), title: title)
    else:
      return (performer: some(splitted[0]), title: splitted[1])

  if title.startswith performer & " -":
    return (performer: some(performer), title: title.split("-", 1)[1])

  return (performer: some(performer), title: title)
