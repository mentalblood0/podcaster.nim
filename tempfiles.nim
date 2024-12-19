import std/[sets, paths, exitprocs, os, sugar]

var temp_files_dir* = "/mnt/tmpfs"
var temp_files: HashSet[string]

proc new_temp_file*(name: string): string =
  result = string temp_files_dir.Path / name.Path
  temp_files.incl result

proc remove_temp_files*() =
  for p in temp_files:
    p.remove_file

add_exit_proc remove_temp_files
set_control_c_hook () {.noconv.} => quit(1)
