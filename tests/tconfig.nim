import std/[cmdline, exitprocs, osproc, random, strutils, strformat],
       std/private/[oscommon, osfiles, ospaths2]

randomize()

const
  nloxvmSource = "src" / "nloxvm.nim"
  loxScriptsFolder* = "tests" / "scripts"

let nloxvmExeName = "nloxvm" & $rand(100_000..999_999)

when defined(windows):
  let nloxvmExe* = nloxvmExeName & ".exe"
else:
  let nloxvmExe* = getCurrentDir() / nloxvmExeName

var nloxvmExeCompiled = false

proc removeNloxvmExe() =
  if fileExists(nloxvmExe):
    discard tryRemoveFile(nloxvmExe)

proc compilenloxvm() =
  if (not fileExists(nloxvmExe)) or (not nloxvmExeCompiled):
    if not dirExists("src"):
      quit("`src` folder not found.", 72)

    if not fileExists(nloxvmSource):
      quit(fmt"`{nloxvmSource}` file not found.", 72)

    let
      options = join(commandLineParams() & @[fmt"-o:{nloxvmExeName}"], " ")
      cmdLine = fmt"nim c {options} {nloxvmSource}"

    echo "  ", cmdLine

    let (_, exitCode) = execCmdEx(cmdLine)

    if (exitCode != 0) or (not fileExists(nloxvmExe)):
      quit(fmt"Unable to compile `{nloxvmSource}`.", 70)

    nloxvmExeCompiled = true

    addExitProc(removeNloxvmExe)

proc nloxvmCompiled*(): bool =
  compilenloxvm()

  result = nloxvmExeCompiled

proc nloxvmTest*(script: string): tuple[output: string, exitCode: int] =
  compilenloxvm()

  let scriptFull = loxScriptsFolder / script

  result = execCmdEx(fmt"{nloxvmExe} {scriptFull}")
