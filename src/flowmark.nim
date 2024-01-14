import std/syncio
import std/options
import std/cmdline
import flowmarkpkg/flowmark
import flowmarkpkg/read

# Usage:
# flowmark       -    start repl.
# flowmark [file]    -    use [file] as input.
# flowmark -v    -    show version.
# flowmark -h    -    show help.
# flowmark -i [file] -    use [file] as input (repl mode.)
when isMainModule:
  var prompt = "% "
  var file = stdin
  var replMode = false
  if paramCount() >= 1:
    if paramStr(1) == "-v":
      echo "0.1.0"
      quit(0)
    elif paramStr(1) == "-h":
      echo ("""
Usage:
flowmark       -    start repl.
flowmark [file]    -    use [file] as input.
flowmark -v    -    show version.
flowmark -h    -    show help.
flowmark -i [file] -    use [file] as input (repl mode.)
""")
      quit(0)
    elif paramStr(1) == "-i":
      replMode = true
      if paramCount() >= 2:
        file = open(paramStr(2), fmRead)
        registerSourceFile(file, paramStr(2))
    else:
      file = open(paramStr(1), fmRead)
      registerSourceFile(file, paramStr(1))
  else:
    registerSourceFile(file, "__stdin__")
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
      if not pres: break
      reportAllError()



  
