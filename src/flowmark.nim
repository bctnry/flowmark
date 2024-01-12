import std/syncio
import std/options
import std/cmdline
import flowmarkpkg/flowmark
import flowmarkpkg/read

# Usage:
# flowmark -v    -    show version.
# flowmark -h    -    show help.
# flowmark -i    -    show repl.
# flowmark -f [file]    -    use [file] as input.
when isMainModule:
  var prompt = ""
  var file = stdin
  if paramCount() >= 1:
    if paramStr(1) == "-v":
      echo "0.1.0"
      quit(0)
    elif paramStr(1) == "-h":
      echo ("""
Usage:
flowmark -v    -    show version.
flowmark -h    -    show help.
flowmark -i    -    start repl.
flowmark -f [file]    -    use [file] as input.
""")
      quit(0)
    elif paramStr(1) == "-i":
      prompt = "% "
    elif paramCount() >= 2 and paramStr(1) == "-f":
      file = open(paramStr(2), fmRead)

  registerReadingsource(file)
  initEnv()
  while true:
    stdout.write(prompt)
    stdout.flushFile()
    let z = readStr()
    if z.isNone(): break
    let pres = process(z.get())
    if not pres: break

  if file != stdout: file.close()

  
