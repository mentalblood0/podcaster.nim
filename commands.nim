import std/[strformat, logging, osproc, strutils, sequtils, strtabs, streams]

import common

type
  BandcampError* = object of AssertionDefect
  BandcampNoVideoFormatsFoundError* = object of BandcampError
  BandcampNoTracksOnPageError* = object of BandcampError
  DurationNotAvailableError* = object of ValueError

  YtDlpNetworkError* = object of IOError
  SslUnexpectedEofError* = object of YtDlpNetworkError
  UnableToConnectToProxyError* = object of YtDlpNetworkError
  ReadTimedOutError* = object of YtDlpNetworkError
  UnableToFetchPoTokenError* = object of YtDlpNetworkError
  IncompleteReadError* = object of YtDlpNetworkError

proc check_substring_exceptions(command_output: string) =
  if "No video formats found!;" in command_output:
    raise new_exception(BandcampNoVideoFormatsFoundError, command_output)
  if "The page doesn't contain any tracks;" in command_output:
    raise new_exception(BandcampNoTracksOnPageError, command_output)
  if "SSL: UNEXPECTED_EOF_WHILE_READING" in command_output:
    raise new_exception(SslUnexpectedEofError, command_output)
  if "Unable to connect to proxy" in command_output:
    raise new_exception(UnableToConnectToProxyError, command_output)
  if "Read timed out." in command_output:
    raise new_exception(ReadTimedOutError, command_output)
  if "Unable to fetch PO Token for mweb client" in command_output:
    raise new_exception(UnableToFetchPoTokenError, command_output)
  if "IncompleteRead" in command_output:
    raise new_exception(IncompleteReadError, command_output)

type CommandProcess = object
  command: string
  args: seq[string]
  process: Process

func command_string(p: CommandProcess): string =
  p.command & " " & p.args.map(quote_shell).join(" ")

proc new_command_process*(command: string, args: seq[string]): CommandProcess =
  result = CommandProcess(
    command: command,
    args: args,
    process: start_process(
      command,
      args = args,
      options = {po_use_path, po_std_err_to_std_out},
      env = new_string_table({"http_proxy": ytdlp_proxy, "https_proxy": ytdlp_proxy}),
    ),
  )
  log(lvl_debug, result.command_string)

proc wait_for_exit*(p: CommandProcess): string =
  try:
    do_assert p.process.wait_for_exit == 0
  except:
    result = p.process.output_stream.read_all
    log(lvl_warn, &"command '{p.command_string}' failed:\n{result}")
    check_substring_exceptions(result)
    raise
  result = p.process.output_stream.read_all
  check_substring_exceptions(result)
  p.process.close

proc execute*(command: string, args: seq[string]): string =
  while true:
    try:
      return wait_for_exit command.new_command_process args
    except YtDlpNetworkError:
      continue
