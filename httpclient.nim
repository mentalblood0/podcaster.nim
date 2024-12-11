import std/httpclient
import std/options

proc get_telegram_http_client*(): HttpClient =
  new_http_client()

var ytdlp_proxy*: Option[string]

proc get_ytdlp_http_client*(): HttpClient =
  if is_some ytdlp_proxy:
    new_http_client(proxy = new_proxy ytdlp_proxy.get)
  else:
    new_http_client()
