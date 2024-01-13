# Flowmark

A text macro language.

## Build

Requires Nim 2.0.0.

``` bash
nimble build
```

## Examples

```
\def(Factorial,(\
  \if.eq(<1>,0,\
    0,\
    (\if.eq(<1>,1,1,(\mult.int(<1>,\call(Factorial,\sub.int(<1>,1))))))\
  )\
));
\init.macro(Factorial);
\print(\call(Factorial,5)(
));
```

```
\def.free($,(\print((
))));
\def(Hanoi,\
  (\if.eq(<1>,0,,\
    (\if.eq(<1>,1,\
      (\print(Move from <from> to <to>)$),\
      (\call(Hanoi,\sub.int(<1>,1),<from>,<via>,<to>)\
      \print(Move from <from> to <to>)$\
      \call(Hanoi,\sub.int(<1>,1),<via>,<to>,<from>))\
    ))\
  ))\
);
\init.macro(Hanoi,,from,to,via);
\print(\call(Hanoi,3,A,C,B));
```

