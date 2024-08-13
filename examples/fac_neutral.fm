\def.macro(Factorial,(\
  \ifeq.int(<1>,0,\
    0,\
    (\ifeq.int(<1>,1,1,(\mult.int(<1>,\call(Factorial,\sub.int(<1>,1))))))\
  )\
));
\call(Factorial,5)\call(Factorial,5)\call(Factorial,5)(
)\
\((Run with:
    flowmark -e test.txt ./examples/fac_neutral.fm
Should write "120120120" into test.txt.))