# Flowmark

Flowmark is a text macro language heavily influenced by TRAC. For an overview of TRAC, see [here](https://sebastian.graphics/blog/trac-language-part-1.html).

## Build

Requires Nim 2.0.0.

``` bash
nimble build
```

## Examples

```
\def.macro(Factorial,(\
  \ifeq.int(<1>,0,\
    0,\
    (\ifeq.int(<1>,1,1,(\mult.int(<1>,\call(Factorial,\sub.int(<1>,1))))))\
  )\
));
\print(\call(Factorial,5)(
));
```

```
\def.free($,(\print((
))));
\def.macro(Hanoi,from,to,via,\
  (\ifeq.int(<1>,0,,\
    (\ifeq.int(<1>,1,\
      (\print(Move from <from> to <to>)$),\
      (\call(Hanoi,\sub.int(<1>,1),<from>,<via>,<to>)\
      \print(Move from <from> to <to>)$\
      \call(Hanoi,\sub.int(<1>,1),<via>,<to>,<from>))\
    ))\
  ))\
);
\print(\call(Hanoi,3,A,C,B));
```

## Editor support

An Emacs major mode can be found [here](https://github.com/bctnry/flowmark-mode.el).

