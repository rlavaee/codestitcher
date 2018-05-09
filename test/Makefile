LEVEL=..
CC=$(LEVEL)/build/llvm/bin/clang
CFLAGS=-flto -O3
LDFLAGS=-B$(LEVEL)/build/binutils/bin/
AR=$(LEVEL)/build/binutils/bin/ar
ARFLAGS=--plugin $(LEVEL)/build/llvm/lib/LLVMgold.so

all: optimize

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

test_util.a: test_util.o
	$(AR) rcs $(ARFLAGS) $@ $<

compile: test.o test_util.a
	$(CC)  $(LDFLAGS) $(CFLAGS) -Wl,-plugin-opt,-emit-bb-symbols $^ -o test

profile: compile
	$(LEVEL)/build/perf/perf record -e instructions:u --branch-filter any,u -o perf.data -- ./test

layout: profile
	ruby $(LEVEL)/scripts/gen_layout.rb -r test -p perf.data -L CS -D 4096

optimize: layout test.o test_util.a
	$(CC)  $(LDFLAGS) $(CFLAGS) -Wl,-plugin-opt,-bb-layout=cs -Wl,-plugin-opt,-emit-bb-symbols test.o test_util.a -o test

clean:
	rm -rf test.cs test.orig test test.layout.cs perf.data* *.o *.a
