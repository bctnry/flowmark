## Line-col aware reading procedures.

import std/options
import std/syncio

var line: int = 0
var col: int = 0

proc resetLineCol*(): void =
  line = 0
  col = 0

proc getLineCol*(): tuple[line: int, col: int] =
  return (line: line, col: col)

var meta = ';'
proc changeMeta*(x: char): void =
  meta = x

proc readStr*(source: File = stdin): Option[string] =
  var res: string = ""
  try:
    while true:
      let ch = source.readChar()
      if ch == meta: return some(res)
      case ch:
        of '\n':
          line += 1
          col = 0
        else:
          col += 1
      res.add(ch)
  except:
    if res.len() > 0: return some(res)
    else: return none(string)
    
