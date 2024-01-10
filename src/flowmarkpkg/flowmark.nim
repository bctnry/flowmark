import std/tables
import std/syncio
import activebuffer

type
  FncallType = enum
    NEUTRAL
    ACTIVE
  Fncall = ref object
    fntype*: FncallType
    mark*: seq[int]
  MacroPieceType = enum
    GAP
    TEXT
  MacroPiece = ref object
    case pt*: MacroPieceType
    of GAP:
      gapnum*: int
    of TEXT:
      content*: string
  Macro = ref object
    fp*: int
    pieceList*: seq[MacroPiece]
  FMError = ref object
    line*: int
    col*: int
    reason*: string
  ExecVerdict = ref object
    shouldContinue*: bool
    res*: string

proc `$`(x: FncallType): string =
  return (
    case x:
      of NEUTRAL: "NEUTRAL"
      of ACTIVE: "ACTIVE"
  )
proc `$`(x: Fncall): string =
  return "Fncall(" & $x.fntype & "," & $x.mark & ")"

var neutral: string = ""
var active: seq[string] = @[]
const idle: string = "\\print(% )\\print(\\read.str)"
var meta: char = ';'
var fncalls: seq[Fncall] = @[]
var forms: Table[string,Macro]
var freeformMacros: Table[string,string]
var errorList: seq[FMError]
  
proc getargs(x: seq[int]): seq[string] =
  var res: seq[string] = @[]
  if x.len() <= 0: return res
  var i = 1
  while i < x.len():
    res.add(neutral[x[i-1]..<x[i]])
    i += 1
  return res

proc readStrTillMeta*(): string =
  var res: string = ""
  try:
    while true:
      let ch = stdin.readChar()
      # echo "getch=", ch
      if ch == meta: return res

      res.add(ch)
  except:
    return res
  
proc performOperation(): ExecVerdict =
  let fncall = fncalls.pop()
  let args = getargs(fncall.mark)
  neutral = neutral[0..<fncall.mark[0]]
  var shouldContinue = true
  var res = ""
  case args[0]:
    of "read.str":
      res = readStrTillMeta()
    of "print":
      stdout.write(args[1])
      stdout.flushFile()
      res = ""
    of "halt":
      shouldContinue = false
    of "test":
      res = if args[1] == args[2]: "yes" else: "no"
    else:
      res = ""
  return ExecVerdict(shouldContinue: shouldContinue, res: res)


proc currentPieceLen(x: seq[string]): int =
  return x[^1].len()
  
proc process*(initActive: string = idle, reloadIdle: bool = true): void =
  forms = initTable[string,Macro]()
  freeformMacros = initTable[string,string]()
  neutral = ""
  active = @[initActive]
  errorList = @[]
  var line = 0
  var col = 0
  var i = 0
  var activeLen = active.currentPieceLen()
  while true:
    activeLen = active.currentPieceLen()
    if i >= activeLen:
      neutral = ""
      if active.len() > 1:
        discard active.pop()
        activeLen = active.currentPieceLen()
      else:
        if reloadIdle:
          active[0] = idle
          activeLen = active.currentPieceLen()
          i = 0
          continue
        else:
          break
    elif active[^1][i] == '(':
      var i_1 = i+1
      var cnt = 0
      while i_1 < activeLen and cnt >= 0:
        if active[^1][i_1] == '(': cnt += 1
        elif active[^1][i_1] == ')': cnt -= 1
        i_1 += 1
      if cnt >= 0:
        neutral = ""
        if active.len() > 1:
          discard active.pop()
          activeLen = active.currentPieceLen()
        else: active[0] = idle
        i = 0
        continue
      else:
        neutral &= active[^1][i+1..<i_1-1]
        i = i_1
        continue
    elif active[^1][i] == '\\':
      i += 1
      if i >= activeLen:
        neutral = ""
        if active.len() > 1: discard active.pop()
        else: active[0] = idle
        i = 0
        continue
      elif active[^1][i] == '(' or (active[^1][i] == '\\' and i+1 < activeLen and active[^1][i+1] == '('):
        var i_1 = if (i < activeLen and active[^1][i] == '('): i+1 else: i+2
        var cnt = 0
        while i_1 < activeLen and cnt >= 0:
          if active[^1][i_1] == '(': cnt += 1
          elif active[^1][i_1] == ')': cnt -= 1
          i_1 += 1
        if cnt >= 0:
          neutral = ""
          if active.len() > 1: discard active.pop()
          else: active[0] = idle
          i = 0
          continue
        else:
          i = i_1
          continue
      elif active[^1][i] == ' ' or active[^1][i] == '\t':
        var i_1 = i
        while i_1 < activeLen and (active[^1][i] == ' ' or active[^1][i] == '\t'): i_1 += 1
        if i_1 >= activeLen:
          neutral = ""
          if active.len() > 1: discard active.pop()
          else: active[0] = idle
          i = 0
          continue
        elif active[^1][i_1] == '\\':
          i = i_1 + 1
          continue
        else:
          i = i_1
          continue
      else:
        var fntype: FncallType = ACTIVE
        if active[^1][i] == '\\':
          fntype = NEUTRAL
          i += 1
        if active[^1][i] in "#~`$%^&": continue
        var i_1 = i
        while i_1 < activeLen and not (active[^1][i_1] in " \t()"): i_1 += 1
        if i_1 == i+1 and i_1 >= activeLen:
          neutral = ""
          if active.len() > 1: discard active.pop()
          else: active[0] = idle
          i = 0
          continue
        # NOTE: fnName here can't be empty since that case is already handled above.
        let fnName = active[^1][i..<i_1]
        fncalls.add(Fncall(fntype: fntype, mark: @[neutral.len()]))
        neutral &= fnName
        fncalls[^1].mark.add(neutral.len())
        if i_1 >= activeLen or active[^1][i_1] != '(':
          # NOTE: this case act as if the right paren has reached; we have to do
          #       everything here.
          var fnres = performOperation()
          if not fnres.shouldContinue: break
          if fntype == ACTIVE:
            active[^1] = fnres.res & active[^1][i_1..<activeLen]
            i = 0
            continue
          elif fntype == NEUTRAL:
            neutral &= fnres.res
            i = i_1
            continue
        else:
          i = i_1+1
          continue
    elif active[^1][i] == '@':
      if i+1 < activeLen:
        neutral.add(active[^1][i+1])
        i += 2
      else:
        neutral.add(active[^1][i])
        i += 1
      continue
    # TODO: add support for freeform macro
    elif active[^1][i] == ',':
      if fncalls.len() < 0:
        neutral.add(',')
      else:
        fncalls[^1].mark.add(neutral.len())
      i += 1
      continue
    elif active[^1][i] == ')':
      let latestFncall = fncalls[^1]
      latestFncall.mark.add(neutral.len())
      var fnres = performOperation()
      if not fnres.shouldContinue: break
      if latestFncall.fntype == ACTIVE:
        active[^1] = fnres.res & active[^1][i+1..<activeLen]
        i = 0
        continue
      elif latestFncall.fntype == NEUTRAL:
        neutral &= fnres.res
        i += 1
        continue
    elif active[^1][i] in "\n\r\v":
      i += 1
      continue
    else:
      neutral.add(active[^1][i])
      i += 1
      continue


