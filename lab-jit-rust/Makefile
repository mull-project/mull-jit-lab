ifeq (, $(LLI))
define LLI_ERROR_MESSAGE

Provide LLI (path to lli).

The easiest way to get lli is to `brew install llvm`.

Then do:
LLI=/usr/local/opt/llvm/bin/lli make ...


endef
$(error $(LLI_ERROR_MESSAGE))
endif

default: compile run

compile:
	mkdir -p target/debug
	rustc jitrust.rs -Z print-link-args --verbose --crate-name jitrust --crate-type lib -g --test --out-dir target/debug --emit=dep-info,link,llvm-ir,llvm-bc -L dependency=target/debug -L dependency=target/debug/deps

run:
	./target/debug/jitrust

run_normal:
	cargo test

lli:
	$(LLI) -load \
				 /Users/Stanislaw/.rustup/toolchains/stable-x86_64-apple-darwin/lib/libstd-f5a209a9.dylib \
         -load \
				 /Users/Stanislaw/.rustup/toolchains/stable-x86_64-apple-darwin/lib/libtest-f5a209a9.dylib \
         ./target/debug/jitrust.bc

clean:
	rm -rfv target/

