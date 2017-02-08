# lab-jit-haskell

Haskell needs LLVM 3.7 to produce bitcode.

```
brew install llvm@3.7
```

## TODO: missing math.h header

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

The problem can be reduced to the following command:

```
echo '#include <math.h>' | clang-3.7 -xc -v -
clang version 3.7.1 (tags/RELEASE_371/final)
Target: x86_64-apple-darwin16.4.0
Thread model: posix
 "/usr/local/Cellar/llvm@3.7/3.7.1/lib/llvm-3.7/bin/clang" -cc1 -triple x86_64-apple-macosx10.12.0 -emit-obj -mrelax-all -disable-free -main-file-name - -mrelocation-model pic -pic-level 2 -mthread-model posix -mdisable-fp-elim -masm-verbose -munwind-tables -target-cpu core2 -target-linker-version 274.2 -v -dwarf-column-info -resource-dir /usr/local/Cellar/llvm@3.7/3.7.1/lib/llvm-3.7/bin/../lib/clang/3.7.1 -fdebug-compilation-dir /Users/Stanislaw/Projects/mull-jit-lab/lab-jit-haskell -ferror-limit 19 -fmessage-length 118 -stack-protector 1 -mstackrealign -fblocks -fobjc-runtime=macosx-10.12.0 -fencode-extended-block-signature -fmax-type-align=16 -fdiagnostics-show-option -fcolor-diagnostics -o /var/folders/yp/lp9sdywn7gd68_9v8l4wd4gr0000gn/T/--9b798f.o -x c -
clang -cc1 version 3.7.1 based upon LLVM 3.7.1 default target x86_64-apple-darwin16.4.0
ignoring nonexistent directory "/usr/include"
#include "..." search starts here:
#include <...> search starts here:
 /usr/local/include
 /usr/local/Cellar/llvm@3.7/3.7.1/lib/llvm-3.7/bin/../lib/clang/3.7.1/include
 /System/Library/Frameworks (framework directory)
 /Library/Frameworks (framework directory)
End of search list.
<stdin>:1:10: fatal error: 'math.h' file not found
#include <math.h>
         ^
1 error generated.
```


