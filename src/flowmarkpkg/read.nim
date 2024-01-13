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

var sourceFile: File = stdin
proc registerSourceFile*(f: File): void =
  sourceFile = f

proc readStrFromSourceFile*(): Option[string] =
  return readStr(sourceFile)
    
proc readCharFromSourceFile*(): Option[char] =
  try:
    let ch = sourceFile.readChar()
    if ch == '\n':
      line += 1
      col = 0
    else:
      col += 1
    return some(ch)
  except:
    return none(char)

proc readLineFromSourceFile*(): Option[string] =
  var res: string = ""
  try:
    while true:
      let ch = source.readChar()
      res.add(ch)
      if ch == '\n':
        line += 1
        col = 0
        return some(res)
      else:
        col += 1
  except:
    if res.len() > 0: return some(res)
    else: return none(string)
  
  
