import std/[strformat, logging, osproc, strutils, sequtils, strtabs, streams]

import common

type
  CommandRecoverableError* = object of IOError
  CommandFatalError* = object of IOError

var recoverable_error_output_substring* =
  @[
    "SSL: UNEXPECTED_EOF_WHILE_READING", "Unable to connect to proxy",
    "Read timed out.", "Unable to fetch PO Token for mweb client", "IncompleteRead",
    "Remote end closed connection without response",
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

func command_string(command: string, args: seq[string]): string =
  command & " " & args.map(quote_shell).join(" ")

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
  lvl_debug.log command_string(result.command, result.args)

proc process_substring_exceptions(output: string) =
  for s in recoverable_error_output_substring:
    if s in output:
      lvl_warn.log &"command failed:\n{output}"
      raise new_exception(CommandRecoverableError, output)
  for s in fatal_error_output_substrings:
    if s in output:
      lvl_warn.log &"command failed:\n{output}"
      raise new_exception(CommandFatalError, output)

proc wait_for_exit*(p: CommandProcess): string =
  let exit_code = p.process.wait_for_exit
  let stdout = p.process.output_stream.read_all
  let stderr = p.process.error_stream.read_all
  p.process.close()
  process_substring_exceptions(stderr)
  if exit_code != 0:
    let error_text = &"command failed:\n{stderr}"
    lvl_warn.log error_text
    raise new_exception(AssertionDefect, error_text)
  return stdout

proc execute*(command: string, args: seq[string]): string =
  while true:
    try:
      return wait_for_exit command.new_command_process args
    except CommandRecoverableError:
      continue

proc execute_immediately*(command: string, args: seq[string]): string =
  lvl_debug.log command_string(command, args)
  result = exec_process(command, args = args, options = {po_use_path})
  process_substring_exceptions result
