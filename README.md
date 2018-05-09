# Codestitcher
Codestitcher enables interprocedural basic block code layout optimization on Linux platforms.

It relies on LBR technology (last branch record), which is available on most Intel CPUs.

To install:
  * run ./install.sh
  * This downloads the source directories for Linux kernel, Gold linker, and LLVM onto your machine (about 2GBs),
  * patches them with the codestitcher patches (in the patch directory) and then builds llvm, binutils, and Linux perf
  utility.
  * The install script is stateful: if it crashes at one point, you will not lose the prior accomplished steps. In order to run
  a clean installation from scratch, run ./install.sh clean

To test:
  * cd test
  * make optimize
    - This compiles the base program with "clang -flto -Wl,-plugin-opt,-emit-bb-symbols", and using the gold linker.
    - Then it profiles the program using the built Linux perf utility (This step requires that your CPU has LBR) and store that
    profile in "perf.data".
    - Then, it finds the optimal Codestitcher basic block layout (CS) for the program, by running "./scripts/gen_layout.rb" with 
    appropriate flags.
    - Finally, it recompiles the program with "clang -flto -Wl,-plugin-opt,-emit-bb-symbols -Wl,-plugin-opt,-bb-layout=cs" to let
    clang use the generated basic block layout.
    
    
    
