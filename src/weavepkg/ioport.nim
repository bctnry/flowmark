type
  StringOutputPortManager* = ref object
    portCounter: int
    portTable: seq[string]
    currentPortId: int

proc makeStringOutputPortManager(): StringOutputPortManager =
  StringOutputPortManager(portCounter: 1,
                          portTable: @[""],
                          currentPortId: 0)

proc allOutputPort*(x: StringOutputPortManager): seq[string] =
  return x.portTable

proc newOutputPort*(x: StringOutputPortManager): int =
  x.portTable.add("")
  let res = x.portCounter
  x.portCounter += 1
  return res

proc writeToOutputPort*(x: StringOutputPortManager, i: int, s: string): void =
  x.portTable[i] &= s

proc writeToCurrentOutputPort*(x: StringOutputPortManager, s: string): void =
  x.portTable[x.currentPortId] = x.portTable[x.currentPortId] & s

proc setCurrentOutputPort*(x: StringOutputPortManager, i: int): void =
  x.currentPortId = i

proc getCurrentOutputPortContent*(x: StringOutputPortManager): string =
  x.portTable[x.currentPortId]

let OUT* = makeStringOutputPortManager()
let WARN* = makeStringOutputPortManager()
let ERROR* = makeStringOutputPortManager()

for _ in 0..<10:
  discard OUT.newOutputPort()
discard WARN.newOutputPort()
discard ERROR.newOutputPort()
OUT.currentPortId = 0
WARN.currentPortId = 0
ERROR.currentPortId = 0


