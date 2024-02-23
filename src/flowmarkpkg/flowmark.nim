import std/tables
import std/syncio
import std/options
import std/strutils
import std/sequtils
import std/strformat
import activebuffer
import read
import ioport
import path

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
    fileName*: string
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
var keywords: Table[string,Macro]

proc `$`(x: ActiveBufferPiece): string =
  return "ABP(" & $x.i & "," & x.buf & ")"
proc `$`(x: ActiveBuffer): string =
  return x.mapIt($it).join(",")

proc getNeutral*(): string = neutral

type
  SourceFileStackEntry = ref object
    line*: int
    col*: int
    name*: string
    f*: File
var sourceFileStack: seq[SourceFileStackEntry] = @[]

proc registerSourceFile*(f: File, name: string): void =
  sourceFileStack.add(SourceFileStackEntry(line: 0, col: 0, name: name, f: f))

proc useSourceFile(path: string): void =
  let f = open(path, fmRead)
  registerSourceFile(f, path)

proc readStr*(source: var SourceFileStackEntry): Option[string] =
  let meta = getMeta()
  var res: string = ""
  try:
    while true:
      let ch = source.f.readChar()
      if ch == meta: return some(res)
      case ch:
        of '\n':
          source.line += 1
          source.col = 0
        else:
          source.col += 1
      res.add(ch)
  except:
    if res.len() > 0: return some(res)
    else: return none(string)

# NOTE: readStrFromSourceFile and similar functions returns none when the latest imported
#       source file ends; the interpreter loop might have just quitted upon that. fix this
#       so that the next-to-latest imported source file could be read after.
    
proc readStrFromSourceFile*(): Option[string] =
  while sourceFileStack.len() > 0:
    let res = sourceFileStack[^1].readStr()
    if res.isNone():
      discard sourceFileStack.pop()
      continue
    return res
  return none(string)
    
proc readCharFromSourceFile*(): Option[char] =
  while sourceFileStack.len() > 0:
    let sf = sourceFileStack[^1]
    try:
      let ch = sf.f.readChar()
      return some(ch)
    except:
      discard sourceFileStack.pop()
      continue
  return none(char)

proc readLineFromSourceFile*(): Option[string] =
  while sourceFileStack.len() > 0:
    let sf = sourceFileStack[^1]
    var res: string = ""
    try:
      while true:
        let ch = sf.f.readChar()
        res.add(ch)
        if ch == '\n':
          return some(res)
    except:
      if res.len() > 0: return some(res)
      else:
        discard sourceFileStack.pop()
        continue
  return none(string)

proc getCurrentSourceFile(): SourceFileStackEntry =
  return sourceFileStack[^1]
    
proc getCurrentLineCol*(): tuple[line: int, col: int] =
  return (line: sourceFileStack[^1].line, col: sourceFileStack[^1].col)

proc getCurrentFileName*(): string =
  return sourceFileStack[^1].name

proc registerError(reason: string): void =
  let fn = getCurrentFileName()
  let lc = getCurrentLineCol()
  errorList.add(FMError(line: lc.line, col: lc.col, fileName: fn, reason: reason))

# NOTE: this is called by src/flowmark.nim, not here.
proc reportAllError*(): void =
  for x in errorList:
    stderr.write(x.fileName & "(" & $(x.line+1) & "," & $(x.col+1) & "): " & x.reason & "\n")
    stderr.flushFile()
  errorList = @[]

proc defineForm(name: string, body: string): void =
  forms[name] = Macro(fp: 0, pieceList: @[MacroPiece(ptype: TEXT, content: body)])

proc defineFreeformMacro(sequence: string, body: string): void =
  freeformMacros[sequence] = body

proc safeIndex[T](x: seq[T], i: int, def: T): T =
  if i >= x.len(): return def
  else: return x[i]

proc expandMacro(form: seq[MacroPiece], argList: seq[string]): string =
  var res: seq[string] = @[]
  for p in form:
    case p.ptype:
      of TEXT:
        res.add(p.content)
      of GAP:
        res.add(argList.safeIndex(p.gapnum-1, ""))
  return res.join("")
  
proc callForm(name: string, call: seq[string]): Option[string] =
  if not forms.hasKey(name): return none(string)
  return some(forms[name].pieceList.expandMacro(call[2..<call.len()]))
  
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

proc validBit(x: string): bool =
  var i = 0
  while i < x.len():
    if not (x[i] in "01"): return false
    i += 1
  return true

proc andBit(x: string, y: string): bool =
  discard "fix this"
  var i = max(x.len(), y.len()) - 1
  
proc initMacro(form: seq[MacroPiece], argList: seq[string]): seq[MacroPiece] =
  var mappingTable: Table[string,int] = initTable[string,int]()
  for i in 0..<argList.len():
    mappingTable[argList[i]] = i+1
  var newPieceList: seq[MacroPiece] = @[]
  for p in form:
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
  return newPieceList
  
  
proc makeMacro(name: string, call: seq[string]): void =
  if not forms.hasKey(name): return
  let argList = call[2..<call.len()]
  let newPieceList = forms[name].pieceList.initMacro(argList)
  forms[name].pieceList = newPieceList

proc defineKeyword(name: string, call: seq[string]): void =
  let body = call[^1]
  let initForm = @[MacroPiece(ptype: TEXT, content: body)]
  keywords[name] = Macro(fp: 0, pieceList: initform)
  keywords[name].pieceList = initForm.initMacro(call[1..<call.len()-1])
  
proc readStrTillMeta*(fromFile: File = stdin): string =
  let s = readStr(fromFile)
  return if s.isNone(): "" else: s.get()

proc updateCurrentLine(x: int): void =
  if active.len() > 1: return
  getCurrentSourceFile().line = x
proc updateCurrentCol(x: int): void =
  if active.len() > 1: return
  getCurrentSourceFile().col = x
proc updateCurrentLineColByChar(x: char): void =
  if active.len() > 1: return
  let f = getCurrentSourceFile()
  if x == '\n' or x == '\v':
    f.line += 1
    f.col = 0
  else:
    f.col += 1
proc updateCurrentLineCol(st: int, e: int): void =
  if active.len() > 1: return
  for i in st..<e: active[0].buf[i].updateCurrentLineColByChar()

# This calls the function, like the "apply" in the eval/apply loop.
proc performOperation(): ExecVerdict =
  let fncall = fncalls.pop()
  let args = getargs(fncall.mark)
  # echo "args=", args
  neutral = neutral[0..<fncall.mark[0]]
  var shouldContinue = true
  var res = ""
  case args[0]:
    # Miscellaneous primitives
    of "halt":
      shouldContinue = false
      shouldReplContinue = false
    of "debug.list_names":
      discard "fix this"
      res = ""
    of "set.meta":
      if args.len() >= 2:
        changeMeta(args[1][0])
    of "reset.meta":
      changeMeta(';')
    of "path":
      if args.len() < 2:
        registerError("Path required for \\path")
      else:
        registerPathResolvingBase(args[1])
      res = "" 
    of "import":
      if args.len() < 2 or args[1].strip().len() <= 0:
        registerError("Module name required for \\import")
      else:
        let arg1 = args[1].strip()
        let p = arg1.resolveModuleByName()
        if p.isNone():
          registerError(&"Cannot find module {arg1}")
        else:
          let fileP = p.get()
          useSourcefile(fileP)
      res = ""

    # Form bookkeeping & macro-related
    of "def":
      defineForm(args[1], args[2])
      res = ""
    of "def.free":
      let sequence = args.safeIndex(1, "")
      if sequence.len() <= 0:
        registerError("Cannot define empty sequence as freeform macro")
      else:
        let content = args.safeIndex(2, "")
        defineFreeformMacro(sequence, content)
      res = ""
    of "def.macro":
      defineForm(args[1], args[^1])
      let makeMacroArgList = args[0..<args.len()-1]
      makeMacro(args[1], makeMacroArgList)
      res = ""
    of "def.keyword":
      defineKeyword(args[1], args)
      res = ""
    of "init.macro":
      if args.len() < 2 or args[1].len() <= 0:
        registerError("Form name required for \\init.macro")
      elif not forms.hasKey(args[1]):
        registerError("Form " & args[1] & " is not yet defined at this point")
      else:
        makeMacro(args[1], args)
      res = ""
    of "copy":
      if args[2].len() <= 0:
        registerError("Form name required for \\copy")
      elif not forms.hasKey(args[1]):
        registerError("Form " & args[1] & " is not yet defined at this point")
      else:
        forms[args[2]] = forms[args[1]]
        res = ""
    of "move":
      if args[2].len() <= 0:
        registerError("Form name required for \\move")
      elif not forms.hasKey(args[1]):
        registerError("Form " & args[1] & " is not yet defined at this point")
      else:
        forms[args[2]] = forms[args[1]]
        forms.del(args[1])
        res = ""
    of "del":
      if args.len() < 2 or args[1].len() <= 0:
        registerError("Form name required for \\del")
      else:
        forms.del(args[1])
        res = ""
    of "del.all_keywords":
      keywords.clear()
      res = ""
    of "del.all_free":
      freeformMacros.clear()
      res = ""
    of "del.all":
      keywords.clear()
      forms.clear()
      freeformMacros.clear()
      res = ""
    of "del.keyword":
      if args.len() < 2 or args[1].len() <= 0:
        registerError("Keyword name required for \\del.keyword")
      elif not keywords.hasKey(args[1]):
        registerError(&"Keyword {args[1]} is not yet defined at this point")
      else:
        keywords.del(args[1])
        res = ""
    of "del.all_macros":
      forms.clear()
      res = ""
    of "del.free":
      if args.len() < 2 or args[1].len() <= 0:
        registerError("Form name required for \\del.free")
      elif not freeformMacros.hasKey(args[1]):
        registerError("Freeform " & args[1] & " is not yet defined at this point")
      else:
        freeformMacros.del(args[1])
        res = ""

    # Full calling & partial calling
    of "call":
      let callres = callForm(args[1], args)
      if callres.isNone():
        registerError("Cannot find form named " & args[1])
        res = ""
      else:
        res = callres.get()
    of "recite.reset":
      if args.len() < 2 or args[1].len() <= 0:
        registerError("Form name required for \\recite.reset")
      elif not forms.hasKey(args[1]):
        registerError(&"Form " & args[1] & " is not yet defined at this point")
      else:
        forms[args[1]].fp = 0
        res = ""

    # Forward-reading primitives
    of "next.char":
      let ch = readCharFromSourceFile()
      let f = getCurrentSourceFile()
      var chsh = ""
      if not ch.isNone():
        let c = ch.get
        chsh.add(c)
        if c == '\n':
          f.line += 1
          f.col = 0
        else:
          f.col += 1
        res = chsh
      else:
        res = ""
    of "next.string":
      let s = readLineFromSourceFile()
      if not s.isNone():
        res = s.get()
        let f = getCurrentSourceFile()
        f.line += 1
        f.col = 0
      else:
        res = ""

    # Algorithmic primitives
    of "add.int":
      res = $(args[1].strip().parseInt() + args[2].strip().parseInt())
    of "sub.int":
      res = $(args[1].strip().parseInt() - args[2].strip().parseInt())
    of "mult.int":
      res = $(args[1].strip().parseInt() * args[2].strip().parseInt())
    of "div.int":
      res = $(args[1].strip().parseInt() div args[2].strip().parseInt())
    of "add.float":
      res = $(args[1].strip().parseFloat() + args[2].strip().parseFloat())
    of "sub.float":
      res = $(args[1].strip().parseFloat() - args[2].strip().parseFloat())
    of "mult.float":
      res = $(args[1].strip().parseFloat() * args[2].strip().parseFloat())
    of "div.float":
      res = $(args[1].strip().parseFloat() / args[2].strip().parseFloat())

    # I/O primitives
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
    of "print.free":
      stdout.write(freeformMacros[args[1]])
      stdout.flushFile()
    of "out":
      for i in 1..<args.len():
        OUT.writeToCurrentOutputPort(args[i])
      res = ""
    of "set.out":
      OUT.setCurrentOutputPort(args[1].strip().parseInt)
    of "reset.out":
      OUT.setCurrentOutputPort(0)
      res = ""
    of "new.out":
      let r = OUT.newOutputPort()
      res = $r
    of "warn":
      for i in 1..<args.len():
        WARN.writeToCurrentOutputPort(args[i])
      res = ""
    of "error":
      for i in 1..<args.len():
        ERROR.writeToCurrentOutputPort(args[i])
      res = ""

    # Branching
    of "ifeq":
      res = if args[1] == args[2]: args[3] else: args[4]
    of "ifeq.int":
      res = if args[1].strip().parseInt() == args[2].strip().parseInt(): args[3] else: args[4]
    of "ifeq.float":
      res = if args[1].strip().parseInt() == args[2].strip().parseInt(): args[3] else: args[4]
    of "ifne":
      res = if args[1] != args[2]: args[3] else: args[4]
    of "ifne.int":
      res = if args[1].strip().parseInt() != args[2].strip().parseInt(): args[3] else: args[4]
    of "ifne.float":
      res = if args[1].strip().parseInt() != args[2].strip().parseInt(): args[3] else: args[4]

    else:
      # check for custom keyword.
      var keywordFound = false
      for kw in keywords.keys:
        if args[0] == kw:
          res = keywords[kw].pieceList.expandMacro(args[1..<args.len()])
          keywordFound = true
          break
      if not keywordFound:
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

# NOTE:
# The source file reading process is done in src/flowmark.nim; this only processes one
# command at a time. The loop in src/flowmark.nim does not advance file's line&col num;
# for better error reporting we do that here.
# Since all "extra" appendage to the left-end of the active string during the evaluation
# process is done by pushing the appendage to the active string stack, the very bottom
# of the active string stack would be always the *actual* source file string, so we
# only advance current file's line&col when we consume characters from that string.
proc process*(source: string = idle): bool =
  # echo "form=", forms
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
      updateCurrentLineCol(i, i_1)
      if cnt >= 0:
        neutral = ""
        registerError("Right parenthesis required")
        echo active
        if active.len() > 1:
          discard active.pop()
          activeLen = active.currentPieceLen()
          i = active.currentPieceI()
        else:
          discard active.pop()
          break
        continue
      else:
        neutral &= active[^1].buf[i+1..<i_1-1]
        i = i_1
        active.setCurrentPieceI(i)
        continue
    elif active[^1].buf[i] == '\\':
      i += 1
      updateCurrentLineColByChar('\\')
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
        updateCurrentLineCol(i, i_1)
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
      elif active[^1].buf[i] in " \t\n\r\v":
        var i_1 = i
        while i_1 < activeLen and (active[^1].buf[i_1] in " \t\n\r\v"): i_1 += 1
        updateCurrentLineCol(i, i_1)
        i = i_1
        active.setCurrentPieceI(i)
        continue
      else:
        var fntype: FncallType = ACTIVE
        if active[^1].buf[i] == '\\':
          fntype = NEUTRAL
          i += 1
          updateCurrentLineColByChar('\\')
        if active[^1].buf[i] in "#~`$%^&":
          active.setCurrentPieceI(i)
          continue
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
        updateCurrentLineCol(i, i_1)
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
          updateCurrentLineColByChar('(')
          active.setCurrentPieceI(i)
          continue
    elif active[^1].buf[i] == '@':
      updateCurrentLineColByChar('@')
      if i+1 < activeLen:
        neutral.add(active[^1].buf[i+1])
        updateCurrentLineColByChar(active[^1].buf[i+1])
        i += 2
      else:
        neutral.add(active[^1].buf[i])
        i += 1
      active.setCurrentPieceI(i)
      continue
    elif active[^1].buf[i] == ',':
      if fncalls.len() <= 0:
        neutral.add(',')
      else:
        fncalls[^1].mark.add(neutral.len())
      i += 1
      active.setCurrentPieceI(i)
      updateCurrentLineColByChar(',')
      continue
    elif active[^1].buf[i] == ')':
      if fncalls.len() > 0:
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
        updateCurrentLineColByChar(')')
      else:
        neutral.add(active[^1].buf[i])
        updateCurrentLineColByChar(')')
        i += 1
        active.setCurrentPieceI(i)
    elif active[^1].buf[i] in "\n\r\v":
      if active[^1].buf[i] in "\n\v":
        updateCurrentLine(getCurrentSourceFile().line+1)
        updateCurrentCol(0)
      i += 1
      active.setCurrentPieceI(i)
      continue
    else:
      var ffmFound = false
      for ffm in freeformMacros.keys:
        if i+ffm.len() <= activeLen:
          if active[^1].buf[i..<i+ffm.len()] == ffm:
            updateCurrentLineCol(i, i+ffm.len())
            i += ffm.len()
            active.setCurrentPieceI(i)
            active.pushNew(freeformMacros[ffm])
            i = active.currentPieceI()
            activeLen = active.currentPieceLen()
            ffmFound = true
            break
      if ffmFound: continue
      neutral.add(active[^1].buf[i])
      updateCurrentLineColByChar(active[^1].buf[i])
      i += 1
      active.setCurrentPieceI(i)
      continue
  return shouldReplContinue

