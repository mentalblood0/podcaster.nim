import std/[strformat, logging, osproc, strutils, sequtils, strtabs, streams]

import common

type
  CommandRecoverableError* = object of IOError
  CommandFatalError* = object of IOError

var recoverable_error_output_substring* =
  @[
    "SSL: UNEXPECTED_EOF_WHILE_READING", "Unable to connect to proxy",
    "Read timed out.", "Unable to fetch PO Token for mweb client", "IncompleteRead",
    "Remote end closed connection without response", "Cannot connect to proxy.",
    "Failed to establish a new connection: [Errno -3] Temporary failure in name resolution",
  ]

var fatal_error_output_substrings* =
  @[
    "No video formats found!;", "The page doesn't contain any tracks;",
    "Sign in to confirm your age", ": Premieres in ",
    ": Requested format is not available",
    "Postprocessing: Error opening output files: Invalid argument",
    "members-only content like this video",
  ]

type CommandProcess = object
  command: string
  args: seq[string]
  process: Process

func command_string(cp: CommandProcess): string =
  cp.command & " " & cp.args.map(quote_shell).join(" ")

proc new_command_process*(command: string, args: seq[string]): CommandProcess =
  result = CommandProcess(
    command: command,
    args: args,
    process: start_process(
      command,
      args = args,
      options = {po_use_path},
      env = new_string_table({"http_proxy": ytdlp_proxy, "https_proxy": ytdlp_proxy}),
    ),
  )
  lvl_debug.log command_string result

proc wait_for_exit*(p: CommandProcess): string =
  p.process.input_stream.close()
  result = p.process.output_stream.read_all
  let stderr = p.process.error_stream.read_all
  let exit_code = p.process.wait_for_exit
  p.process.close()
  let error_message =
    &"command {p.command_string} failed with exit code {exit_code}:\n{stderr}"
  for s in recoverable_error_output_substring:
    if s in stderr:
      lvl_warn.log error_message
      raise new_exception(CommandRecoverableError, "see last warning")
  for s in fatal_error_output_substrings:
    if s in stderr:
      lvl_warn.log error_message
      raise new_exception(CommandFatalError, "see last warning")
  if exit_code != 0:
    lvl_warn.log error_message
    raise new_exception(AssertionDefect, "see last warning")

proc execute*(command: string, args: seq[string]): string =
  while true:
    try:
      return wait_for_exit command.new_command_process args
    except CommandRecoverableError:
      continue
