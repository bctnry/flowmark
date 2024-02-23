import std/syncio
import std/options
import std/cmdline
import flowmarkpkg/flowmark
import flowmarkpkg/read
import flowmarkpkg/path
import cmdargparse
import std/tables
import std/strutils
import flowmarkpkg/ioport
from std/paths import getCurrentDir, parentDir, Path

let helpStr = """
Usage: flowmark [options] [file]
flowmark         -    start repl.
flowmark [file]  -    use [file] as input (but don't start repl)

Options:
    -v          -    show version.
    -h          -    show help.
    -i          -    start repl after the source file is processed.
    -o [files]  -    specify the out-port target file
    -e [file]   -    specify the neutral string target file
"""

when isMainModule:
  var lastNeutral: string = ""
  var prompt = "% "
  var file = stdin
  var replMode = false
  var args: seq[string] = @[]
  var outTarget: seq[string] = @[]
  var neutralTarget: string = ""
  for i in 0..<paramCount():
    args.add(paramStr(i+1))
  if paramCount() >= 1:
    let table = @[
      (fullKey: "--version", shortKey: "-v", takeValue: false),
      (fullKey: "--help", shortKey: "-h", takeValue: false),
      (fullKey: "--interactive", shortKey: "-i", takeValue: false),
      (fullKey: "--out-target", shortKey: "-o", takeValue: true),
      (fullKey: "--neutral-target", shortKey: "-e", takeValue: true),
    ].parseCmdArgs(args)
    # echo table
    # quit(0)
    if table[0].hasKey("--version"):
      echo "0.1.0"
      quit(0)
    elif table[0].hasKey("--help"):
      echo helpStr
      quit(0)
    else:
      if table[0].hasKey("--interactive"):
        replMode = true
      if table[0].hasKey("--out-target"):
        outTarget = table[0]["--out-target"].strip().split(",")
      if table[0].hasKey("--neutral-target"):
        neutralTarget = table[0]["--neutral-target"]
      if table[1] >= paramCount():
        registerSourceFile(file, "__stdin__")
        registerPathResolvingBase(getCurrentDir().string)
      else:
        let fileName = paramStr(table[1]+1)
        file = open(fileName,  fmRead)
        registerSourceFile(file, fileName)
        registerPathResolvingBase(fileName.Path.parentDir.string)
  else:
    registerSourceFile(file, "__stdin__")
    registerPathResolvingBase(getCurrentDir().string)
    replMode = true

  initEnv()
  if file != stdin:
    while true:
      let z = readStrFromSourceFile()
      if z.isNone(): break
      let pres = process(z.get())
      if not pres: break
      reportAllError()
  if file != stdin: file.close()
  if replMode:
    prompt = "% "
    while true:
      stdout.write(prompt)
      stdout.flushFile()
      let z = readStr(stdin)
      if z.isNone(): break
      let pres = process(z.get())
      lastNeutral = getNeutral()
      if not pres: break
      reportAllError()
  if neutralTarget.len() > 0:
    let neutralDumpFile = open(neutralTarget, fmWrite)
    neutralDumpFile.write(getNeutral())
    neutralDumpFile.flushFile()
    neutralDumpFile.close()
  if outTarget.len() > 0:
    let allOutResult = OUT.allOutputPort().len()
    let bound = min(allOutResult, outTarget.len())
    for i in 0..<bound:
      let s = outTarget[i].strip()
      if s.len() > 0:
        let f = open(s, fmWrite)
        f.write(OUT.allOutputPort()[i])
        f.flushFile()
        f.close()

