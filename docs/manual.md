# Flowmark User Manual

(very early draft. subject to change.)

## Introduction

Flowmark is a macro language influenced by TRAC T64.

### A taste of Flowmark

The following is an example of the factorial function

```
\def(Factorial,(\
  \ifeq.int(<1>,0,\
    0,\
    (\ifeq.int(<1>,1,1,(\mult.int(<1>,\call(Factorial,\sub.int(<1>,1))))))\
  )\
));
\init.macro(Factorial);
\print(\call(Factorial,5));
```

The following is an example of a solution to the Tower of Hanoi problem. 

```
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
```

### Difference between Flowmark and TRAC T64

+ Hashes `#` that starts a function call is replaced with slashes `\\`.
+ Function call syntax is slightly different (`\func(arg1,arg2,...)` vs. `#(func,arg1,arg2,...)`).
+ Default meta character in Flowmark is semicolon `;` instead of apostrophe `'`.
+ In T64 spaces are preserved, forcing many TRAC source code to be left-aligned. In Flowmark, any consequential whitespaces after a slash `\` is ignored altogether; this allows one to indent their code; if whitespaces are needed, one could always use the protective parentheses.
+ The at-sign `@` is used as some kind of "global escape character"; it is guaranteed that the next character after an at-sign `@` (except when it's in protective parentheses) is retained regardless of any syntax rules and previously defined macros.
+ The way to define text macros is slightly different; in Flowmark it's like a combination of T64 and T84. (explained later)
+ It's possible to extend the processing algorithm to a limited content by using something called a /freeform macro/. (explained later)

### How to use the CLI

```
Usage: flowmark [options] [file]
flowmark         -    start repl.
flowmark [file]  -    use [file] as input (but don't start repl)

Options:
    --version, -v                 -    show version.
    --help, -h                    -    show help.
    --interactive, -i             -    start repl after the source file is processed.
    --out-target, -o [files]      -    specify the out-port target file
    --neutral-target, -e [file]   -    specify the neutral string target file
```

A few more specifications on the options:

+ The "long name" for the options can be replaced with the short name and vice versa, e.g. using `-o` instead of `--out-target`)
+ The `[files]` the option `-o` takes is a list of file names separated with comma `,`.

## The processing algorithm

People who had previous experience with TRAC or any similar languages (e.g. SAM76) would find this at least somewhat similar; due to how the function call syntax in Flowmark differs from TRAC, the algorithm is a little more complex than the one in the latter.

The actual algorithm goes as follows:

1. Prepare the following:
   * A string buffer for the "neutral" string
   * A stack of string buffer for the different layers of "active" string. We'll refer to this stack as "the active string stack". From now on, when we say "the active string", we mean the active string buffer at the top of this stack.
   * A stack of lists for storing locations of start & ending of function names and their arguments. All the locations would be locations in the /neutral string buffer/. We'll refer to this stack as "the calling stack".
2. Initialize the neutral string buffer with an empty string and the active string buffer with the source text.
3. Starting from the left-end of the active string, check the beginning of the string:
   * If there isn't any character for checking (i.e. the active string is empty), initialize both the neutral string buffer and the active string buffer as in step 2, i.e. clears the neutral string buffer and load the idling procedure into the active string buffer. Restart step 3.
   * Or, if the first character is a left parenthesis =(= , find the /matching/ right parenthesis =)=.
     * If such a matching right parenthesis cannot be found, discard everything in neutral and active string buffer, initialize both as in step 2, then restart step 3. A syntax error should be reported here.
     * Or, if such a right parenthesis can indeed be found, the contents between the left and this right parenthesis (not including the parentheses) is inserted to the right-end of neutral string buffer. Restart step 3 from the next character of this right parenthesis.
   * Or, if the beginning of the active string is a slash =\=, this could mean the following things:
     * An active or a neutral function call begins.
     * A "whitespace escape sequence" begins. (explained below)
     Check the following characters.
     * If there isn't any more character, discard everything in neutral and active string buffer, initialize both as in step 2, then restart step 3. (_{This situation is handled as if it forms a call to some "null function" which returns an empty string.})
     * Or, if it's followed by:
       * A left parenthesis =(= (the full prefix would be =\(= );
       * Or a slash followed by a left parenthesis =\(= (the full prefix would be =\\(= ),
       (_{it's also handled as if it forms a call to some "null function" which returns an empty string regardless of its arguments.}) Find the matching right parenthesis and remove everything related (including the slashes, the parentheses and the characters within), and restart step 3 at the next character of the right parenthesis. (_{Users may use this semantics as some kind of commenting construct.})
     * Or, if it's followed by a whitespace character (i.e. spaces, tabs, carriage returns, linefeeds, vertical tabs), keep examine the active string and take as much such characters as possible from the left-end, until the right-end of the active string or a non-whitespace character is reached. The slash and these whitespace characters are then discarded. Restart step 3. (_{This is seen as the same as the "null function call" situation above.})
     * Or, if it's followed by a slash =\= (the full prefix would be =\\= ), this function call would be a *neutral* call. Record this and then do the same thing as the next branch starting from the next character.
     * Or, if the following character is not one of the ones which can start a freeform macro, i.e. not one of hash =#=, tilde =~=, backtick =`=, dollar sign =$=, percent sign =%=, circumflex =^=, ampersand =&= and underscore =_=, this is the beginning of a normal *active* function call. Examine the active string and take as much non-space/tab characters as possible from the left-end, until the right-end of the active string, a space, a tab, a left parenthesis =(= or a right parenthesis =)= is reached. (_{The characters taken would be the name of the function that would be called.}) Record the current length of the neutral string as the beginning of a function call, and append them to the right-end of the neutral string. Now, consider the ending situation this time:
       + If a left parenthesis is reached, (_{then this funcion call comes with an argument list.}) Record the current length of neutral string as the end of the function name (and the beginning of the first argument) and remove this left parenthesis from the active string.
       + Or else, (_{this function call has a function name but does not come with an argument list, thus it should be treated as if the right parenthesis for the arglist of this call already occured.}) Check if there's a function with the specified name.
	 + If the name is empty, delete the neutral string and the active string, initialize them as in step 2, then restart step 3.
	 + If the name is not empty and is a defined function, then perform the operation accordingly and remove this function call from the calling stack.
	 + If the name is not empty and is not a defined function, report a name error, remove the registered call from the calling stack.
       Then, restart step 3.
     * Or else, the slash itself is added to the right-end of the neutral string. Restart step 3.
   * Or, if the first character is a comma =,= , the actions taken depend on if there's a function call registered already.
     * If there is not, remove the comma from the active string, add it to the right-end of neutral string, and restart step 3.
     * If there is, then it shows that an argument for the latest registered function call is ending. Mark the current length of neutral string as the end of the last argument. Restart step 3.
   * Or, if the first character is a right parenthesis =)= , check if there's a function call already registered.
     * If there is not, remove the parenthesis from the active string and add it to the neutral string.
     * If there is, then:
       1. Retrieve the /latest/ registered function call with the recorded marks and extract the function name and all the arguments with it from the neutral string.
       2. Remove this function call from the stack.
       3. Delete everything in the neutral string buffer after the beginning of the latest registered function call.
       4. Perform the operation accordingly; but if the call is to a name that's not a built-in function, do nothing (maybe a name error should be reported here).
       Then, depending on whether (1) it returns a null value (i.e. empty string), (2) it's an active function call or a neutral function call and (3) the latest registered function call is to a built-in function name:
       * If it returns null, then no operation is done.
       * If it's a call to a function name that's not built-in, treat it as if it returns null, i.e. no opertion is done.
       * If it's an active function call, the nominated result of the operation is inserted to the /left-end/ of the active string; i.e. the result of an active function call immediately gets processed next.
       * If it's a neutral function call, the nominated result of the operation is appended to the /right-end/ of the neutral string.
       After all this is done, remove the function call from the stack and restart step 3.
   * Or, if the first character is an at-sign =@=, then the next character after that, no matter what kind of character it is, is appended to the right-end of the neutral string. At-sign =@= in Flowmark is used as a "global escape character". Restart step 3 from the next character /after/ the character that's being appended.
   * Or, if the beginning of the string has a prefix that has a previously defined freeform macro, push the corresponding string onto the active string stack, and restart step 3. (_{This rule is put here since one cannot simply append the corresponding string to the left-end of the activ string because forward-reading (explaind later) primitives directly act upon the active string /previous to the expansion of the freeform macro/.})
   * Or, if none of the rules mentioned above applies, remove the first character from the active string and add it to the neutral string. Restart step 3.

Note that this description of algorithm does not mention "idling procedure" like TRAC; while it's possible in Flowmark to use an idling procedure like TRAC, this implementation does not use one and its REPL is implemented separately instead.

## Defining text macros in Flowmark

In Flowmark there are two kinds of macros, called normal macro and freeform macro respectively. 

### Defining normal macro

Normal macro is the same as plain-old macros in T64. In Flowmark, defining a normal macro is done in two steps:

+ Define a form with `\def`;
+ Turn the defined form with `\init.macro`.

The syntax for normal macro in Flowmark is taken from TRAC T84: gaps are represented by integers surrounded with angle brackets `<>`. For example:

```
\def(STR,(The quick brown <2> jumps over the lazy <1>.));
\init.macro(STR);
```

is equivalent to this in T64:

```
#(ds,STR,(The quick brown FOX jumps over the lazy DOG.))'
#(ss,STR,DOG,FOX)'
```

One can also use _named gaps_ like this:

```
\def(STR,(The quick brown <FOX> jumps over the lazy <DOG>.));
\init.macro(STR,DOG,FOX);
```

The end result is the same.

### Pieces

A *piece* (in Flowmark terminology) is a minimal semantically meaningful substring. A piece can be one of the followings:

+ A single character that is not a part of any special construct (either by themselves being not a part of any special construct or by escaping with at-sign `@`);
+ A function call, both active and neutral;
+ A whitespace escape sequence;
+ A freeform macro name (explained later);

The concept of piece in Flowmark is quite important; we'll see this very soon.

### Forward-reading

Flowmark supports *forward-reading*, which allows text macros themselves to read the upcoming source text themselves instead of delegating the reading to the processing algorithm; this is similar to reader macro in LISPs, the difference being forward-reading occurs at runtime.

### Freeform macro

A *freeform macro* is a kind of "special text macro" that's directly expanded during the execution of the processing algorithm instead of full/partial calling (i.e. by primitives like `call` and `recite.*`)

The name for a freeform macro can only contain the following characters:

+ A hash `#`;
+ A tilde `~`;
+ A backtick <code>`</code>;
+ A dollar sign `$`;
+ A percent sign `%`;
+ A circumflex `^`;
+ An ampersand `&`;
+ An underscore `_`;

Although freeform macros do not have the ability to take an argument list, it can still handle the upcoming text by expanding into forward-reading primitives. Consider this example for defining syntax sugar for superscripts, subscripts and math mode in a possible typesetting library; one would define the freeform macro `^`, `_` and `$$` as follows:

```
  \def.free($$,(\toggle(mode.math)));
  \def.free(^,(\format.superscript(\\next.piece)));
  \def.free(_,(\format.subscript(\\next.piece)));
  $$a^2+b^2=c^2$$
  $$e^(\pi i)=1$$
  $$A_i + B_(ij) <= C_k$$
```

This would be the equivalent to:

```
  \toggle(mode.math)a\format.superscript(2)+b\format.superscript(2)=c\format.superscript(2)\toggle(mode.math)
  \toggle(mode.math)e\format.superscript(\pi i)=1\toggle(mode.math)
  \toggle(mode.math)A\format.subscript(i) + B\format.subscript(ij) <= C\format.subscript(k)\toggle(mode.math)
```

## Document generation in Flowmark

Since Flowmark was originally intended to be the foundation language of a typesetting toolkit like TeX, instead of Standard Output/Standard Error (which are separate but both are normally redirected to the console) like in POSIX-compliant systems, in Flowmark there's Default Print/Default Neutral/Default Out:

+ Default Neutral simply means the neutral string buffer after the execution of the last command group. It's intended for text macro expansion, e.g. having a Flowmark source file expand into an HTML or Postscript file.
+ Default Print always mean the console. This is where you write your output to if you're writing an interactive program.
+ Default Out refers the current `out` port used by the `\out` primitive ("port" here is a term to refer to a system internal buffer you write to). `out` ports are intended for *generating* files (instead of *expanding* like in Default Neutral).

The content of Default Neutral and Default Out is lost if no target is specified (e.g. by using `-e` and `-o` command line options). Ten output port (ID 0~9) is created upon the startup of Flowmark so one does not need to create new ones most of the time.

## Non-text literals in Flowmark

Flowmark is largely text-oriented, but there are times when numeric or boolean calculations are needed.

There are four kinds (well technically three) of non-text literals in Flowmark:

+ Integers
+ Floating-point numbers (i.e. the ones with decimals)
+ Bit vector
+ Boolean
  + In Flowmark booleans are actually bit vector of length 1.
  
All four of them are (kind of) numeric. Primitives that requires numeric arguments would remove the surrounding whitespaces of the texts passed as arguments and tries to interpret it as corresponding numeric values using certain

### Valid numeric & boolean literals

+ Bit vectors requires the argument text to contain only `0` and `1`.
+ Boolean requires the argument text, after removing surrounding whitespaces, must be `0` or `1`.

### Coercion

+ Integers, 

## Keywords

You can use `\def.keyword(NAME,ARG1,...,BODY)` to define new keywords. The semantics is roughly the same as defining a macro using `\def.macro` except:

+ Keywords are stored in a separate namespace than macros; you can have a keyword and a macro with the same name.
+ You can't `recite` a keyword.

Keywords are intended to have a different syntax for calling; for example, a macro for calculating factorial would be invoked like this:

```
\call(Factorial,5);
```

But if `Factorial` is defined as a keyword, one must invoke it like this:

```
\Factorial(5);
```

Keywords are intended to be a mechanism to extend the language itself


## Primitives

(names tagged with * is still work in progress)

### Miscellaneous primitives

+ `\halt`: Halt any further execution.
+ `\debug.list_names`*:
+ `\set.meta(STR)`: Returns empty string. Set the meta character to the first character of string `STR`.
+ `\reset.meta`: Returns empty string. Set the meta character to semicolon `;`, the default used by Flowmark.

### Form bookkeeping & macro-related primitives

+ `\def(NAME,BODY)`: Returns empty string. Stores `BODY` under the name `NAME`. When `NAME` is an empty string, this has no effect.
+ `\def.free(PAT,BODY)`: Returns empty string. Used to define freeform macros (explained above). `PAT` must not be empty, or else an error is reported.
+ `\def.macro(NAME,ARG1,...,BODY)`: Returns empty string. A combination of `\def` and `\init.macro`. Equivalent to `\def(NAME,BODY)\init.macro(NAME,ARG1,...)`.
+ `\def.keyword(NAME,ARG1,...,BODY)`: Returns empty string. Used to define a keyword.
+ `\init.macro(NAME,ARG1,...)`: Returns empty string. Used to turn already defined forms into normal macros.
+ `\copy(NAME1,NAME2)`: Returns empty string. Copies the form originally defined under the name `NAME1` to the new name `NAME2`. The newly-defind form has its own form pointer. If `NAME1` is not previously defined, an error is reported. If any of the two names are empty string, this has no effect.
+ `\move(NAME1,NAME2)`: Returns empty string. Moves the form from the name `NAME1` to the new name `NAME2`. If `NAME1` is not previously defined, an error is reported. If any of the two names are empty string, this has no effect.
+ `\del(NAME)`: Returns empty string. Remove the form defined under the name `NAME`. If `NAME` is not previously defined, an error is reported. If =NAME= is an empty string, this has no effect.
+ `\del.free(PAT)`: Returns empty string. Remove a freeform macro with the pattern `PAT`. If `PAT` is empty or not previously defined, an error is reported.
+ `\del.keyword(NAME)` *: Returns empty string. Delete a custom-defined keyword.
+ `\del.all`: Returns empty string. Remove all definitions, including freeform macros, normal macros and keywords.
+ `\del.all_macros`: Returns empty string. Remove all normal macros.
+ `\del.all_keywords`: Returns empty string. Remove all custom-defined keywords.
+ `\del.all_free`: Returns empty string. Remove all freeform macros.

### Full calling & partial calling

+ `\call(NAME,ARG1,...)`: Returns the result of filling in the form defined under the name `NAME` with its parameters replaced by `ARG1`, etc.. The full calling primitive; equivalent to `cl` in T64.

Flowmark has the following partial calling primitives; all of them returns empty string when the form the call is referring to (i.e. the `NAME` parameter) does not exist:

+ `\recite.reset(NAME)`*: Returns empty string. Resets the form pointer of the form defined under the name `NAME`. Equivalent to `cr` in T64.
+ `\recite.char(NAME,Z)`*: Returns the single character pointed by the form pointer of the form defined under the name `NAME`. The form pointer of `NAME` is increased by one character. If the form pointer is already at the right-most position, `Z` is returned instead. Equivalent to `cc` in T64.
+ `\recite.nchar(NAME,N,Z)` * : Returns the first `N` character from the form defined under the name `NAME` starting from the form pointer. `N` is treated as an integer. If `N` is not a valid-form integer, a warning is reported, and its first valid-form integer substring is used as a replacement. If there's less than `N` characters left, they're all returned, and the result would be shorter than `N` characters. If the form pointer is already at the right-most position, `Z` is returned instead. Equivalent to `cn` in T64.
+ `\recite.next_piece(NAME,Z)` * : Returns the next piece after the form pointer of the form defined under the name =NAME=.
+ `\recite.to_gap(NAME,Z)` * :
+ `\recite.to_pattern(NAME,PAT,Z)` * :

### Forward-reading primitives

+ `\next.piece` * :
+ `\next.char`: Read the next character from the current source file. Returns an empty string when end-of-file is reached.
+ `\next.line`: Reads till the next linefeed from current source file. The result contains the read linefeed character. Returns an empty string when end-of-file is reached.

### Algorithmic primitives

+ `\add.int(ARG1,...)`, `\sub.int(ARG1,...)`, `\mult.int(ARG1,...)`, `\div.int(ARG1,...)`
+ `\add.float(ARG1,...)`, `\sub.float(ARG1,...)`, `\mult.float(ARG1,...)`, `\div.float(ARG1,...)`
+ `\eq.int(ARG1,ARG2)` * , `\le.int(ARG1,ARG2)` * , `\ge.int(ARG1,ARG2)` * , `\lt.int(ARG1,ARG2)` * , `\gt.int(ARG1,ARG2)` * :
+ `\eq.float(ARG1,ARG2)` * , `\le.float(ARG1,ARG2)` * , `\ge.float(ARG1,ARG2)` * , `\lt.float(ARG1,ARG2)` * , `\gt.float(ARG1,ARG2)` * :
+ `\and.bit(ARG1,ARG2)` * , `\or.bit(ARG1,ARG2)` * , `\not.bit(ARG1)` * , `\xor.bit(ARG1,ARG2)` * :
+ `\and(ARG1,...)` * :
+ `\or(ARG1,...)` * :
+ `\not(ARG1,...)` * :
+ `\is.empty(ARG1)` * :
+ `\is.int(ARG1)` * : Returns a boolean value indicating if `ARG` is a valid integer, `1` means it **is** valid, `0` means it is not.
+ `\is.float(ARG1)` * :
+ `\is.bit(ARG1)` * :
+ `\to.bit(ARG1,WIDTH)` * : Returns the conversion result of []. `WIDTH` can be empty; when `WIDTH` is empty, 

### I/O primitives

+ `\read.str`:
+ `\read.piece` * :
+ `\print(X)`: Returns empty string. Put `X` to the current print port.
+ `\print.form(NAME)`:
+ `\print.free(PAT)`:
+ `\out(X1,X2,...)`: Returns empty string. Output `X1`, `X2`, ... to the current default output port.
+ `\set.out(ID)`: Returns empty string. Set current output port.
+ `\reset.out`: Returns empty string. Resets the current output port to port 0. (Equivalent to `\set.out(0)`)
+ `\new.out`: Returns a valid integer string. Creates a new output port. The returned integer string would be the ID of the new output port.
+ `\error(X)`: Returns empty string. Put `X` to the current error port.
+ `\warn(X)`: Returns empty string. Put `X` to the current warning port.

### Branching

+ `\ifeq(STR1,STR2,CLAUSE1,CLAUSE2)`:
+ `\ifeq.int(NUM1,NUM2,CLAUSE1,CLAUSE2)`:
+ `\ifeq.float(NUM1,NUM2,CLAUSE1,CLAUSE2)`:
+ `\ifne(STR1,STR2,CLAUSE1,CLAUSE2)`:
+ `\ifne.int(NUM1,NUM2,CLAUSE1,CLAUSE2)`:
+ `\ifne.float(NUM1,NUM2,CLAUSE1,CLAUSE2)`:

