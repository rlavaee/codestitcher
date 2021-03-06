# Codestitcher
Codestitcher enables interprocedural basic block code layout optimization on Linux platforms.

It relies on LBR technology (last branch record), which is available on most Intel CPUs.
For more details, please see our arxiv paper: https://arxiv.org/abs/1810.00905

## To install:
  * run ./install.sh
  * This downloads the source directories for Linux kernel, Gold linker, and LLVM onto your machine (about 2GBs), patches them with the codestitcher patches (in the patch directory) and then builds llvm, binutils, and Linux perf utility. All the installed binaries and libraries will be placed in the build/ directory.
  * Note: The install script is stateful: if it crashes at one point, you will not lose the prior accomplished steps. In order to run a clean installation from scratch, run "./install.sh clean".

## To test:
  * cd test
  * make optimize
    - This compiles the base program with "clang -flto -Wl,-plugin-opt,-emit-bb-symbols", and using the gold linker.
    - Then it profiles the program using the built Linux perf utility (This step requires that your CPU has LBR) and store that
    profile in "perf.data".
    - Then, it finds the optimal Codestitcher basic block layout (CS) for the program, by running "./scripts/gen_layout.rb" with 
    appropriate flags.
    - Finally, it recompiles the program with "clang -flto -Wl,-plugin-opt,-emit-bb-symbols -Wl,-plugin-opt,-bb-layout=cs" to let clang use the generated basic block layout.
    - Test the optimized program's layout by comparing the results of "../build/llvm/bin/llvm-nm --numeric-sort test" and "cat test.layout.cs".
    - Run the optimized program
    - Optional: Try other implemented code layout techniques (PH, PHF, C3, C3F, CSS).

### Large page support
  For large programs (larger than 1MB), passing "-Wl,-plugin-opt,-enable-huge-pages -lhugepage_text_rt -L../build -Wl,-z,max-page-size=0x200000" ensures that the hot code is loaded onto large 2MB pages.
  To test this feature (even though it is not applicable for the provided small test case), run

  * make optimize-lp
