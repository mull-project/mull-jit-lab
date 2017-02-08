# lab-jit-objc

[All selectors unrecognised when invoking Objective-C methods using the LLVM ExecutionEngine](http://stackoverflow.com/questions/10375324/all-selectors-unrecognised-when-invoking-objective-c-methods-using-the-llvm-exec)

## Background

https://twitter.com/gparker/status/783390176978415616

```
@gparker Any hints on how could we make it with JIT loader?

@sbpankevich There is no good answer today. There are answers for some code, but no straightforward solution that handles everything.

@sbpankevich For example, the JIT could call or emit calls to sel_getUid() when it needs a selector value.

@sbpankevich ...but handling all of ObjC piecemeal like that is a long tail of sadness.

@sbpankevich ObjC code requires the loader to call the runtime to initialize stuff like selectors. Presumably LLVM's JIT loader does not.

@gparker @sbpankevich how can one call the runtime initialization without system loader?
```

