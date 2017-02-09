# lab-jit-haskell

Haskell needs LLVM 3.7 to produce bitcode.

```
brew install ghc
brew install llvm@3.7
```

The following modifications should be made to the Haskell's settings file:

```
...
 ("C compiler command", "clang-3.7"),
 ("C compiler flags", " -m64 -fno-stack-protector -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"),
...
 ("LLVM llc command", "llc-3.7"),
 ("LLVM opt command", "opt-3.7")
```

Most likely there is a better place for tweaking these settings, 
however changing system's `/usr/local/Cellar/ghc/8.0.2/lib/ghc-8.0.2/settings` 
also works.

```
LLI=lli-3.7 make
```

