import std/[strformat, logging, osproc, strutils, sequtils, strtabs, streams]

import common

type
  CommandRecoverableError* = object of IOError
  CommandFatalError* = object of IOError

var recoverable_error_output_substring* =
  @[
    "SSL: UNEXPECTED_EOF_WHILE_READING", "Unable to connect to proxy",
    "Read timed out.", "Unable to fetch PO Token for mweb client", "IncompleteRead",
  ]

var fatal_error_output_substrings* =
  @[
    "No video formats found!;", "The page doesn't contain any tracks;",
    "Sign in to confirm your age",
  ]

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
      options = {po_use_path},
      env = new_string_table({"http_proxy": ytdlp_proxy, "https_proxy": ytdlp_proxy}),
    ),
  )
  log(lvl_debug, result.command_string)

proc wait_for_exit*(p: CommandProcess): string =
  discard p.process.wait_for_exit
  let stdout = p.process.output_stream.read_all
  let stderr = p.process.error_stream.read_all
  for s in recoverable_error_output_substring:
    if s in stderr:
      log(lvl_warn, &"command '{p.command_string}' failed:\n{stderr}")
      raise new_exception(CommandRecoverableError, stderr)
  for s in fatal_error_output_substrings:
    if s in stderr:
      log(lvl_warn, &"command '{p.command_string}' failed:\n{stderr}")
      raise new_exception(CommandFatalError, stderr)
  return stdout

proc execute*(command: string, args: seq[string]): string =
  while true:
    try:
      return wait_for_exit command.new_command_process args
    except CommandRecoverableError:
      continue
