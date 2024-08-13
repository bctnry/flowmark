\def.free($,(\print((
))));
\def(Hanoi,\
  (\ifeq.int(<1>,0,,\
    (\ifeq.int(<1>,1,\
      (\print(Move from <from> to <to>)$),\
      (\call(Hanoi,\sub.int(<1>,1),<from>,<via>,<to>)\
      \print(Move from <from> to <to>)$\
      \call(Hanoi,\sub.int(<1>,1),<via>,<to>,<from>))\
    ))\
  ))\
);
\init.macro(Hanoi,,from,to,via);
\print(\call(Hanoi,3,A,C,B));

