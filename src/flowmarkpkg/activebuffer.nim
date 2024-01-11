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

proc pushNew*(x: var ActiveBuffer, s: string): void =
  x.add(ActiveBufferPiece(i: 0, buf: s))

# INVARIANT: the top of the stack is immediately removed whenever
#            the pointer reaches the right-most position.
proc peekNextCharacter*(x: ActiveBuffer): char =
  return x[^1].buf[x[^1].i]

proc moveToNextCharacter*(x: var ActiveBuffer): void =
  x[^1].i += 1
  if x[^1].i >= x[^1].buf.len(): discard x.pop()

proc currentPieceLen*(x: ActiveBuffer): int =
  return x[^1].buf.len()

proc currentPieceI*(x: ActiveBuffer): int =
  return x[^1].i

proc setCurrentPieceI*(x: var ActiveBuffer, i: int): void =
  x[^1].i = i

proc isEmpty*(x: ActiveBuffer): bool =
  return x.len() == 0
                    
