import std/tables
import std/syncio
import std/options
import std/strutils
import activebuffer
import read


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
    case ptype*: MacroPieceType
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
proc `$`(x: MacroPieceType): string =
  return (
    case x:
      of GAP: "GAP"
      of TEXT: "TEXT"
  )
proc `$`(x: MacroPiece): string =
  return (
    case x.ptype:
      of GAP: "<" & $x.gapnum & ">"
      of TEXT: x.content
  )

proc `$`(x: Macro): string =
  var res = @["Macro[", $x.fp, ",{"]
  for p in x.pieceList:
    res.add($p)
    res.add(",")
  res.add("}]")
  return res.join()

var neutral: string = ""
var active: ActiveBuffer = @[]
const idle: string = "\\print((% ))\\print(\\read.str)"
var fncalls: seq[Fncall] = @[]
var forms: Table[string,Macro]
var freeformMacros: Table[string,string]
var errorList: seq[FMError]
var shouldReplContinue: bool = true

proc defineForm(name: string, body: string): void =
  forms[name] = Macro(fp: 0, pieceList: @[MacroPiece(ptype: TEXT, content: body)])

proc defineFreeformMacro(sequence: string, body: string): void =
  freeformMacros[sequence] = body

proc safeIndex[T](x: seq[T], i: int, def: T): T =
  if i >= x.len(): return def
  else: return x[i]
  
proc callForm(name: string, call: seq[string]): Option[string] =
  if not forms.hasKey(name): return none(string)
  var res: seq[string] = @[]
  for p in forms[name].pieceList:
    case p.ptype:
      of TEXT:
        res.add(p.content)
      of GAP:
        res.add(call.safeIndex(p.gapnum+1, ""))
  return some(res.join(""))
  
proc getargs(x: seq[int]): seq[string] =
  var res: seq[string] = @[]
  if x.len() <= 0: return res
  var i = 1
  while i < x.len():
    res.add(neutral[x[i-1]..<x[i]])
    i += 1
  return res

proc validInteger(x: string): bool =
  var i = 0
  while i < x.len():
    if ord(x[i]) < ord('0') or ord('9') < ord(x[i]): return false
    i += 1
  return true

proc makeMacro(name: string, call: seq[string]): void =
  if not forms.hasKey(name): return
  var mappingTable: Table[string,int] = initTable[string,int]()
  for i in 2..<call.len():
    mappingTable[call[i]] = i-1
  var newPieceList: seq[MacroPiece] = @[]
  for p in forms[name].pieceList:
    if p.ptype == GAP:
      newPieceList.add(p)
      continue
    var i = 0
    let pContentLen = p.content.len()
    var shouldContinueImmediately = false
    var last_i = 0
    while i < pContentLen:
      if p.content[i] == '<':
        var i_1 = i+1
        while i_1 < pContentLen and not (p.content[i_1] in "<>;"):
          i_1 += 1
        if i_1 < pContentLen and p.content[i_1] == '>':
          let idx = p.content[i+1..<i_1]
          let isIndexValidInteger = validInteger(idx)
          let isIndexIncludedInCall = mappingTable.hasKey(idx)
          if isIndexValidInteger or isIndexIncludedInCall:
            newPieceList.add(MacroPiece(ptype: TEXT, content: p.content[last_i..<i]))
            newPieceList.add(MacroPiece(ptype: GAP, gapnum: if isIndexValidInteger: idx.parseInt() else: mappingTable[idx]))
            last_i = i_1+1
          i = i_1+1
        elif i_1 >= pContentLen:
          newPieceList.add(p)
          shouldContinueImmediately = true
          break
        else:
          i = i_1 + 1
          continue
        i = i_1+1
      else:
        i += 1
    if shouldContinueImmediately: continue
    if last_i < pContentLen:
      newPieceList.add(MacroPiece(ptype: TEXT, content: p.content[last_i..<pContentLen]))
  forms[name].pieceList = newPieceList
  
proc readStrTillMeta*(): string =
  let s = readStr()
  return if s.isNone(): "" else: s.get()

# This calls the function, like the "apply" in the eval/apply loop.
proc performOperation(): ExecVerdict =
  let fncall = fncalls.pop()
  let args = getargs(fncall.mark)
  neutral = neutral[0..<fncall.mark[0]]
  var shouldContinue = true
  var res = ""
  case args[0]:
    of "comment":
      res = ""
    of "read.str":
      let readres = readStrTillMeta()
      res = readres
    of "print":
      stdout.write(args[1])
      stdout.flushFile()
      res = ""
    of "print.form":
      stdout.write($forms[args[1]])
      stdout.flushFile()
      res = ""
    of "halt":
      shouldContinue = false
      shouldReplContinue = false
    of "def":
      defineForm(args[1], args[2])
      res = ""
    of "def.free":
      let sequence = args.safeIndex(1, "")
      if sequence.len() <= 0:
        discard nil
        # TODO: report error here.
      else:
        let content = args.safeIndex(2, "")
        defineFreeformMacro(sequence, content)
      res = ""
    of "call":
      let callres = callForm(args[1], args)
      if callres.isNone:
        # TODO: register name error here.
        res = ""
      else:
        res = callres.get()
    of "init.macro":
      makeMacro(args[1], args)
      res = ""
    else:
      res = ""
  return ExecVerdict(shouldContinue: shouldContinue, res: res)


proc reloadActive(str: string = idle): void =
  active[0].buf = idle
  active[0].i = 0

proc initEnv*(): void =
  forms = initTable[string,Macro]()
  freeformMacros = initTable[string,string]()
  neutral = ""
  errorList = @[]
  shouldReplContinue = true

proc process*(source: string = idle): bool =
  active.pushNew(source)
  var i = 0
  var activeLen = active.currentPieceLen()
  while active.len() > 0:
    activeLen = active.currentPieceLen()
    i = active.currentPieceI()
    if active.currentPieceI() >= activeLen:
      if active.len() > 1:
        discard active.pop()
        activeLen = active.currentPieceLen()
        i = active.currentPieceI()
      else:
        break
    elif active[^1].buf[i] == '(':
      var i_1 = i+1
      var cnt = 0
      while i_1 < activeLen and cnt >= 0:
        if active[^1].buf[i_1] == '(': cnt += 1
        elif active[^1].buf[i_1] == ')': cnt -= 1
        i_1 += 1
      if cnt >= 0:
        neutral = ""
        if active.len() > 1:
          discard active.pop()
          activeLen = active.currentPieceLen()
          i = active.currentPieceI()
        else:
          break
        continue
      else:
        neutral &= active[^1].buf[i+1..<i_1-1]
        i = i_1
        active.setCurrentPieceI(i)
        continue
    elif active[^1].buf[i] == '\\':
      i += 1
      if i >= activeLen:
        neutral = ""
        if active.len() > 1:
          discard active.pop()
          activeLen = active.currentPieceLen()
          i = active.currentPieceI()
        continue
      elif active[^1].buf[i] == '(' or (active[^1].buf[i] == '\\' and i+1 < activeLen and active[^1].buf[i+1] == '('):
        var i_1 = if (i < activeLen and active[^1].buf[i] == '('): i+1 else: i+2
        var cnt = 0
        while i_1 < activeLen and cnt >= 0:
          if active[^1].buf[i_1] == '(': cnt += 1
          elif active[^1].buf[i_1] == ')': cnt -= 1
          i_1 += 1
        if cnt >= 0:
          neutral = ""
          if active.len() > 1:
            discard active.pop()
            activeLen = active.currentPieceLen()
            i = active.currentPieceI()
          continue
        else:
          i = i_1
          active.setCurrentPieceI(i)
          continue
      elif active[^1].buf[i] in " \t":
        var i_1 = i
        while i_1 < activeLen and (active[^1].buf[i] == ' ' or active[^1].buf[i] == '\t'): i_1 += 1
        if i_1 >= activeLen:
          neutral = ""
          if active.len() > 1:
            discard active.pop()
            activeLen = active.currentPieceLen()
            i = active.currentPieceI()
          continue
        elif active[^1].buf[i_1] == '\\':
          i = i_1 + 1
          active.setCurrentPieceI(i)
          continue
        else:
          i = i_1
          active.setCurrentPieceI(i)
          continue
      else:
        var fntype: FncallType = ACTIVE
        if active[^1].buf[i] == '\\':
          fntype = NEUTRAL
          i += 1
        if active[^1].buf[i] in "#~`$%^&": continue
        var i_1 = i
        while i_1 < activeLen and not (active[^1].buf[i_1] in " \t\n\r\v()"): i_1 += 1
        if i_1 == i+1 and i_1 >= activeLen:
          neutral = ""
          if active.len() > 1:
            discard active.pop()
            activeLen = active.currentPieceLen()
            i = active.currentPieceI()
          continue
        # NOTE: fnName here can't be empty since that case is already handled above.
        let fnName = active[^1].buf[i..<i_1]
        fncalls.add(Fncall(fntype: fntype, mark: @[neutral.len()]))
        neutral &= fnName
        fncalls[^1].mark.add(neutral.len())
        if i_1 >= activeLen or active[^1].buf[i_1] != '(':
          # NOTE: this case act as if the right paren has reached; we have to do
          #       everything here.
          var fnres = performOperation()
          if not fnres.shouldContinue: break
          if fntype == ACTIVE:
            active[^1].buf = fnres.res & active[^1].buf[i_1..<activeLen]
            i = 0
            active.setCurrentPieceI(i)
            continue
          elif fntype == NEUTRAL:
            neutral &= fnres.res
            i = i_1
            active.setCurrentPieceI(i)
            continue
        else:
          i = i_1+1
          active.setCurrentPieceI(i)
          continue
    elif active[^1].buf[i] == '@':
      if i+1 < activeLen:
        neutral.add(active[^1].buf[i+1])
        i += 2
      else:
        neutral.add(active[^1].buf[i])
        i += 1
      active.setCurrentPieceI(i)
      continue
    elif active[^1].buf[i] == ',':
      if fncalls.len() < 0:
        neutral.add(',')
      else:
        fncalls[^1].mark.add(neutral.len())
      i += 1
      active.setCurrentPieceI(i)
      continue
    elif active[^1].buf[i] == ')':
      let latestFncall = fncalls[^1]
      latestFncall.mark.add(neutral.len())
      var fnres = performOperation()
      if not fnres.shouldContinue: break
      if latestFncall.fntype == ACTIVE:
        active[^1].buf = fnres.res & active[^1].buf[i+1..<activeLen]
        i = 0
        active.setCurrentPieceI(i)
        continue
      elif latestFncall.fntype == NEUTRAL:
        neutral &= fnres.res
        i += 1
        active.setCurrentPieceI(i)
        continue
    elif active[^1].buf[i] in "\n\r\v":
      i += 1
      active.setCurrentPieceI(i)
      continue
    else:
      var ffmFound = false
      for ffm in freeformMacros.keys:
        if i+ffm.len() < activeLen:
          if active[^1].buf[i..<i+ffm.len()] == ffm:
            i += ffm.len()
            active.setCurrentPieceI(i)
            active.pushNew(freeformMacros[ffm])
            i = active.currentPieceI()
            activeLen = active.currentPieceLen()
            ffmFound = true
            break
      if ffmFound: continue
      neutral.add(active[^1].buf[i])
      i += 1
      active.setCurrentPieceI(i)
      continue
  return shouldReplContinue

