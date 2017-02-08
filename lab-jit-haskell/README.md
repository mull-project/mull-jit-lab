# lab-jit-haskell

Haskell needs LLVM 3.7 to produce bitcode.

```
brew install llvm@3.7
```

## TODO

```
$ LLI=FOO make compile
ghc -fllvm example.hs
[1 of 1] Compiling Main             ( example.hs, example.o )
Linking example ...

In file included from /var/folders/yp/lp9sdywn7gd68_9v8l4wd4gr0000gn/T/ghc51234_0/ghc_7.c:1:0: error:
    

In file included from /usr/local/Cellar/ghc/8.0.2/lib/ghc-8.0.2/include/Rts.h:30:0: error:
    

/usr/local/Cellar/ghc/8.0.2/lib/ghc-8.0.2/include/Stg.h:74:10: error:
     fatal error: 'math.h' file not found
#include <math.h>
         ^
1 error generated.
`clang-3.7' failed in phase `C Compiler'. (Exit code: 1)
make: *** [compile] Error 1
```

