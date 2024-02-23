## Line-col aware reading procedures.

import std/options
import std/syncio


var meta = ';'
proc changeMeta*(x: char): void =
  meta = x

proc getMeta*(): char = return meta

proc readStr*(source: File = stdin): Option[string] =
  var res: string = ""
  try:
    while true:
      let ch = source.readChar()
      if ch == meta: return some(res)
      res.add(ch)
  except:
    if res.len() > 0: return some(res)
    else: return none(string)
