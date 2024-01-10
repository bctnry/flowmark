## Active string buffer.
## During the processing algorithm the active string will only be appended from
## the left-end, thus using a stack would be suffice.

type
  ActiveBufferPiece* = ref object
    i*: int
    buf*: string
  ActiveBuffer* = seq[ActiveBufferPiece]

proc activeBufferFromString*(x: string): ActiveBuffer =
  return @[ActiveBufferPiece(i: 0, buf: x)]

proc appendLeft*(x: ActiveBuffer, s: string): ActiveBuffer =
  x.add(ActiveBufferPiece(i: 0, buf: s))
  return r

# INVARIANT: the top of the stack is immediately removed whenever
#            the pointer reaches the right-most position.
proc peekNextCharacter*(x: ActiveBuffer): char =
  return x[^1][x[^1].i]

proc moveToNextCharacter*(x: ActiveBuffer): void =
  x[^1].i += 1
  if x[^1].i >= x[^1].buf.len(): discard x.pop()

proc currentPieceLen*(x: ActiveBuffer): int =
  return x[^1].len()

proc isEmpty*(x: ActiveBuffer): bool =
  return x.len() == 0
                    
