# This is just an example to get you started. A typical hybrid package
# uses this file as the main entry point of the application.

import std/syncio
import std/options
import flowmarkpkg/flowmark

let meta = ';'

proc readStr(): Option[string] =
  var res: string = ""
  try:
    while true:
      let ch = stdin.readChar()
      if ch == meta: return some(res)
      res.add(ch)
  except:
    if res.len() > 0: return some(res)
    else: return none(string)

when isMainModule:
  echo "Flowmark 0.1.0"
  process()

  
