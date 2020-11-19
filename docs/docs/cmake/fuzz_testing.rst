.. _fuzz-testing-top:

============
Fuzz Testing
============

What is fuzz testing?
---------------------
Fuzz testing consists of exercising component methods using data that is more
unusual than the hand-crafted cases test writers tend to provide, with a goal
of exposing possible crashes, memory problems, and a variety of other ill
behavior.

Fuzz testing may also be coverage-driven, with code compiled in a way that
provides feedback to the test driver, such that fuzz data becomes tailored to
exercising all code paths in the program.

We support fuzz testing using the ``clang`` compiler.  Fuzz testing requires a
specially written fuzz testing function to be present in the test driver, and
is then requested by adding ``fuzz`` to the specified ufid.
When fuzz testing, it is helpful to also specify a sanitizer option in the
ufid, such as ``asan`` (the address sanitizer), so that more errors are
detected.

Writing a Fuzz test
-------------------
A fuzz test is simply a ``C`` function with a special name,
``LLVMFuzzerTestOneInput``.  The fuzz testing system calls this function
repeatedly, supplying different data each time, and the function is responsible
for invoking the methods to be tested using this data.  The fuzz testing
library supplies its own custom ``main()`` to perform these calls, so a fuzz
test cannot have its own ``main()``.

Within the BDE system, where we do want to co-locate a fuzz test within the
ordinary test driver, we use a macro to rename ``main`` when building for fuzz
testing.  The build system will define ``BDE_ACTIVATE_FUZZ_TESTING`` when
building for fuzz testing to enable this.

A fuzz test is expected to attempt to crash on the first failure detected.
This might be a "natural" crash, perhaps because the program indirects through
bad pointers, or a deliberate crash via an unhandled exception or a call to
``abort``.  In BDE fuzz tests, a deliberate crash is invoked through the
assertion system, as seen below.  The fuzz testing infrastructure intercepts
such crash attempts, saves the problematic input, reports the failure, and
exits.

A BDE test driver adapted for fuzz testing will include code similar to the
following template, just before ``main()``.  The BDE code base has several
components that have already been modified this way.  Please see those, e.g.,
`ball_patternutil.t.cpp <http://bburl/BPUFuzzTest>`__, for complete examples.

A Fuzz Testing Template
-----------------------
The following is an empty example template for a fuzz testing function.

  .. code-block:: cpp

     // ============================================================================
     //                              FUZZ TESTING
     // ----------------------------------------------------------------------------
     //                              Overview
     //                              --------
     // The following function, 'LLVMFuzzerTestOneInput', is the entry point for the
     // clang fuzz testing facility.  See {http://bburl/BDEFuzzTesting} for details
     // on how to build and run with fuzz testing enabled.
     //-----------------------------------------------------------------------------

     #ifdef BDE_ACTIVATE_FUZZ_TESTING
     #define main test_driver_main
     #endif

     extern "C"
     int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
         // Use the specified 'data' array of 'size' bytes as input to methods of
         // this component and return zero.
     {
         const char *FUZZ   = reinterpret_cast<const char *>(data);
         int         LENGTH = static_cast<int>(size);
         int         test   = 0;

         if (LENGTH > 0) {
             // Use first fuzz byte to select the test case.
             test = (*FUZZ++ & 0xFF) % 100;
             --LENGTH;
         }

         switch (test) { case 0:  // Zero is always the leading case.
           case N: {
             // --------------------------------------------------------------------
             // TESTING 'myFunction'
             //
             // Plan:
             //   Describe how 'myFunction' will be fuzz tested.
             //
             // Testing:
             //   static void myFunction(arg1 value, ...);
             // --------------------------------------------------------------------
         
             // ...  Test myFunction using ASSERT or in other ways ...
           } break;
           // ... other cases ...
           default: {
           } break;
         }

         if (testStatus > 0) {
             BSLS_ASSERT_INVOKE("FUZZ TEST FAILURES");
         }

         return 0;
     }

Generating Fuzz Test Inputs
---------------------------
In BDE testing methodology, there are often table-driven tests where the author
has generated interesting test data by hand, and calls methods with that data,
perhaps varying some other parameter along the way.  It might look something
like the following.

  .. code-block:: cpp

     const char *DATA[] = {
         "Hello",
         "World!",
         "",
         "------------------------------------------------------------",
         "123 123 123 123 123",
     };
     size_t NUM_DATA = sizeof(DATA) / sizeof(*DATA);

     const uint8_t LIMITS[] = { 0, 1, 2, 3, 11, 21, 255 };
     size_t NUM_LIMITS = sizeof(LIMITS) / sizeof(*LIMITS);

     for (size_t i = 0; i < NUM_DATA; ++i) {
         for (size_t j = 0; j < NUM_LIMITS; ++j) {
             int result = obj.method(DATA[i], strlen(DATA[i]), LIMITS[j]);
             ASSERTV(0 == result);
         }
     }

In fuzz testing, we generally don't want to do this.  The intent of fuzz
testing is to have "surprising" inputs, so we want to use the fuzz data as much
as we can, in order to eliminate hidden assumptions in the test data that might
prevent errors from being noticed.  So, if we are writing a fuzz test with the
intent of paralleling the normal test above, we might write it like this.

  .. code-block:: cpp

     // ,,,
     switch (test) {
       case 1: {
         uint8_t limit = 0;
         if (LENGTH > 0) {
             limit = *FUZZ++ & 0xFF;
             --LENGTH;
         }

         int result = obj.method(FUZZ, strnlen(FUZZ, LENGTH), limit);
         ASSERTV(0 == result);
       } break;
       // ...

Rather than keeping tables of strings and limits, we allow the fuzz data to
supply both a limit and a string, and we only test a single case rather than
looping through a set of cases.  The fuzz testing infrastructure will do the
looping for us, and it will come up with combinations of strings and limits
that we might not see in the hand-written data, and that we might miss if we
used the fuzz data only for the string but not for the limit.

What Does A Fuzz Test Test?
---------------------------
Fuzz testing involves a variety of approaches depending on the nature of the
methods to be tested.  It is up to the author of the fuzz test to decide which
approaches are appropriate for the tests being conducted.  Given the fuzz test
skeleton above, fuzz tests may include the usual invocations of ``ASSERTV`` and
related test macros, and any failure will result in the test driver aborting
and thus notifying the fuzz testing machinery that the supplied input has
caused a failure.


    - Acceptance Testing Functions with Wide Contracts:
        Functions with wide contracts claim to accept any input.  Thus, the
        fuzz test may simply invoke such methods with the supplied data.  The
        purpose of such a test is to verify that the method does not crash or
        cause any detectable undefined behavior, but not to check that the
        function produces the correct result.

        .. code-block:: cpp

           obj.wideFun(FUZZ, LENGTH);

    - Acceptance Testing Functions with Narrow Contracts:
        Functions with narrow contracts claim to accept only a limited set of
        inputs.

        - Valid Input:
            The fuzz test may examine the supplied data and call the method to
            be tested only if the data falls within the contract.  If the data
            is valid for the contract, the test again simply verifies that the
            method does not crash or cause detectable undefined behavior.

            .. code-block:: cpp

               if (LENGTH > 5 && FUZZ[0] == 'A' && FUZZ[1] == '(') {
                   obj.narrowFun(FUZZ, LENGTH);
               }

        - Invalid Input:
            The fuzz test may choose to invoke methods with data that the
            narrow contract prohibits to determine whether such out-of-contract
            data is caught and handled by the method, especially when built in
            safe contract modes.  Here, the test uses the
            ``ASSERT_SAFE_PASS/FAIL`` macros to verify that the called method
            detects out-of-contract data and calls the failure handler, or
            processes in-contract data and does not invoke the handler.  If
            there is a crash or other detectable undefined behavior, that too
            will be caught in either case.  Once again, we are not testing if
            the result of the method is correct.

            .. code-block:: cpp

               #ifdef BDE_BUILD_TARGET_EXC
               if (LENGTH > 5 && FUZZ[0] == 'A' && FUZZ[1] == '(') {
                   bsls::AssertTestHandlerGuard g;
                   ASSERT_SAFE_PASS(obj.narrowFun(FUZZ, LENGTH));
               }
               else {
                   bsls::AssertTestHandlerGuard g;
                   ASSERT_SAFE_FAIL(obj.narrowFun(FUZZ, LENGTH));
               }
               #endif

    - Comprehensive Correctness Testing:
        Within any of the above approaches related to contract scope, the fuzz
        test may also choose to verify not only that the called functions do
        not crash, but also that they correctly process their input.  In this
        context, the value of correctness testing depends on the ability to
        provide an independently written "oracle" function that determines
        whether the input is correct and what the results of the method should
        be.  This is not always feasible, since such determination (e.g.,
        well-formedness of XML or JSON) may sometimes be as complex and prone
        to error as the component under test itself.

            .. code-block:: cpp

               bool allNumeric = true;
               for (int i = 0; allNumeric && i < LENGTH; ++i) {
                   allNumeric = '0' <= FUZZ[i] && FUZZ[i] <= '9';
               }
               bool result = obj.checkAllNumeric(FUZZ, LENGTH);
               ASSERTV(allNumeric, result, allNumeric == result);

    .. note:

       How to write fuzz tests involving narrow contracts is still a work in
       progress.  As we develop experience with the fuzz testing process, we
       will be able to refine our guidelines.

Building and Running Fuzz Tests
-------------------------------
BDE libraries and test drivers can be built and linked to enable fuzz testing
using ``clang`` compilers.  It is best to use the most recent version of the
compiler available, as the fuzz testing system is frequently updated.

{{{ internal
Version 10 of ``clang`` is available in the Bloomberg environment as of this
writing.
}}}

When using the ``cmake`` system to build fuzz tests, the test drivers should be
built, but not automatically run.  The ``main()`` routine supplied by the fuzz
testing library takes different arguments than the normal test driver
arguments.

When the executable is run, the ``main()`` function in the fuzz testing library
will repeatedly invoke ``LLVMFuzzerTestOneInput`` with a variety of data.
Once the program detects an error and aborts, the ``clang`` fuzz testing
machinery will save the supplied data that caused the crash in a file named
``crash-...`` for further examination.  The fuzz test may choose to print out
verbose testing information, but note that the normal command-line arguments
that control verbosity do not work due to the custom ``main()``, and the
default fuzz testing output is itself quite verbose.

{{{ internal
In the Bloomberg environment, the ``clang`` compiler and the fuzz testing
runtime libraries may be packaged separately, and the compiler does not know
where to find the runtimes.  If so, the combination of the two must be
installed locally before use, as shown below.
}}}

First, set up the build environment.  In this example, we are requesting a
64-bit fuzz testing build with address sanitizer included, and that version 10
of the ``clang`` compiler be used.  We request safe mode to enable all of the
contract assertions, and optimization in the hope of exposing more possible bad
behavior.

  ::

    $ eval `bde_build_env.py -t dbg_opt_safe_exc_mt_64_asan_fuzz_cpp17 -c clang-10`

{{{ internal

Next, if using a Bloomberg-maintained compiler instance, (e.g., on a general
Linux machine) install a local copy of ``clang`` and its runtime libraries, and
point the compiler environment variables to that installation.  This overrides
the selected compiler configured by ``bde_build_env.py`` above.  (Use the
``--refroot-path`` option to specify the directory where you want the compiler
installed.)

  ::

    $ refroot-install --distribution=unstable --yes --arch amd64 \
      --package clang-10.0 --package compiler-rt-10.0 \
      --refroot-path=/bb/bde/$USER/myclang
    $ export CXX=/bb/bde/$USER/myclang/opt/bb/lib/llvm-10.0/bin/clang++
    $ export  CC=/bb/bde/$USER/myclang/opt/bb/lib/llvm-10.0/bin/clang

}}}

Then configure and build the fuzz test.

  ::

    $ cmake_build.py configure build --targets=ball_patternutil.t --tests=build

Finally, run the fuzz test.  When not invoked with command-line arguments, a
fuzz testing test driver will run forever or until it crashes.  There are a
variety of arguments that control the behavior of the test driver, described
`here <https://llvm.org/docs/LibFuzzer.html#options>`__.  In particular, the
argument ``-max_total_time=N`` will limit the running time to N seconds, and
``-help=1`` will display all available options.

  ::

    $ ./_build/*/ball_patternutil.t -max_total_time=120

If a fuzz test stops due to hitting a specified limit, it exits with a normal
status (0).  If it stops dues to a detected error causing a crash, it exits
with a failed status (1).  Thus, for automated testing, the test can be run
with its output redircted to a discarding device and a time limit specified,
checking the exit status once it's done.

Fuzz testing may also be run incrementally, with initial inputs specified.  If
the test driver is supplied with one or more directories on the command line,
it treats files in those directories as the initial input corpus for fuzz
testing, and will mutate those inputs to derive further test cases, writing
interesting ones back to the first directory.  Providing such a set of initial
inputs can be useful when correct input is highly structured, such that the
fuzz testing procedure may take a long time to find its way there if left
unguided.  (Although in that case, we suggest that a better, or at least
alternate, option is to write test cases that generate structured input using
the fuzz data as a base.)  The corpus directory may start off empty, in which
case fuzz testing will generate and save its data from scratch.


Interpreting Fuzz Test Results
------------------------------
For comprehensive details on the output produced by fuzz testing, see the
documentation `here <https://llvm.org/docs/LibFuzzer.html#output>`__.

The fuzz tester writes output describing what it's doing as it does it, which
id generally not useful or interesting.  On failure (that is, when the test
machinery intercepts an attempt to crash), depending on the nature of the crash
and the sanitizers that are built into the program, the fuzz test will write
additional output to the standard error channel describing what it believes to
be the problem, and whatever data it can provide as to its location.  It will
write the fuzz data that caused the problem to a file named ``crash-...``.

Here is some sample output for a one-line fuzz test that treats the fuzz data
as a pointer and tries to indirect it, which causes an immediate failure.

  .. code-block:: cpp

     extern "C" int LLVMFuzzerTestOneInput(int **f) { return **f == 0; }

  ::

     INFO: Seed: 1428378131
     INFO: Loaded 1 modules   (1 inline 8-bit counters): 1 [0x78d128, 0x78d129), 
     INFO: Loaded 1 PC tables (1 PCs): 1 [0x560bc0,0x560bd0), 
     INFO: -max_len is not provided; libFuzzer will not generate inputs larger than 4096 bytes
     =================================================================
     ==194626==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x602000000050 at pc 0x000000539e25 bp 0x7ffcae0dc970 sp 0x7ffcae0dc968
     READ of size 8 at 0x602000000050 thread T0
         #0 0x539e24  (./ft.t+0x539e24)
         #1 0x440131  (./ft.t+0x440131)
         #2 0x446c91  (./ft.t+0x446c91)
         #3 0x448936  (./ft.t+0x448936)
         #4 0x4309d5  (./ft.t+0x4309d5)
         #5 0x41f4c2  (./ft.t+0x41f4c2)
         #6 0x3dcc01ed1c  (/lib64/libc.so.6+0x3dcc01ed1c)
         #7 0x41f574  (./ft.t+0x41f574)
     
     0x602000000051 is located 0 bytes to the right of 1-byte region [0x602000000050,0x602000000051)
     allocated by thread T0 here:
         #0 0x5366b8  (./ft.t+0x5366b8)
         #1 0x44003b  (./ft.t+0x44003b)
         #2 0x446c91  (./ft.t+0x446c91)
         #3 0x448936  (./ft.t+0x448936)
         #4 0x4309d5  (./ft.t+0x4309d5)
         #5 0x41f4c2  (./ft.t+0x41f4c2)
         #6 0x3dcc01ed1c  (/lib64/libc.so.6+0x3dcc01ed1c)
     
     SUMMARY: AddressSanitizer: heap-buffer-overflow (./ft.t+0x539e24) 
     Shadow bytes around the buggy address:
       0x0c047fff7fb0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
       0x0c047fff7fc0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
       0x0c047fff7fd0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
       0x0c047fff7fe0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
       0x0c047fff7ff0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
     =>0x0c047fff8000: fa fa 00 fa fa fa 00 fa fa fa[01]fa fa fa fa fa
       0x0c047fff8010: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
       0x0c047fff8020: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
       0x0c047fff8030: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
       0x0c047fff8040: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
       0x0c047fff8050: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
     Shadow byte legend (one shadow byte represents 8 application bytes):
       Addressable:           00
       Partially addressable: 01 02 03 04 05 06 07 
       Heap left redzone:       fa
       Freed heap region:       fd
       Stack left redzone:      f1
       Stack mid redzone:       f2
       Stack right redzone:     f3
       Stack after return:      f5
       Stack use after scope:   f8
       Global redzone:          f9
       Global init order:       f6
       Poisoned by user:        f7
       Container overflow:      fc
       Array cookie:            ac
       Intra object redzone:    bb
       ASan internal:           fe
       Left alloca redzone:     ca
       Right alloca redzone:    cb
       Shadow gap:              cc
     ==194626==ABORTING
     MS: 0 ; base unit: 0000000000000000000000000000000000000000
     
     
     artifact_prefix='./'; Test unit written to ./crash-da39a3ee5e6b4b0d3255bfef95601890afd80709
     Base64: 


Debugging Failed Fuzz Tests
---------------------------
Generally speaking, once a problem is detected, testing needs to fall back to
ordinary debugging; fuzz testing tells you that a problem exists with a
specified input, and it is then up to you to locate the problem.  Depending on
the nature of the problem, there may be output from the test program that will
provide clues.  In the sample output above, we see that a memory overflow has
been detected, and the program provides stack traces for where the memory was
allocated, where the overflow happened, and the contents of memory around the
problematic area.  Near the end, we see that the test program has written the
bad input to a file named ``crash-da39a3ee5e6b4b0d3255bfef95601890afd80709``.

The test program can be rerun supplying that file as a command-line argument.
When this is done, only the contents of that file are supplied as input data to
the fuzz testing subroutine, making it easy to repeat the failure.

The sanitizer infrastructure provides some support for debugging; see, for
example, `AddressSanitizerAndDebugger
<https://github.com/google/sanitizers/wiki/AddressSanitizerAndDebugger>`__.
There is a well-known program location, ``__sanitizer::Die``, that is called
after the program prints its report and before it exits; setting a breakpoint
there allows for tracing back to where the error occurred.  A debugging session
for the above failure might begin as follows::

    $ gdb ./ft.t
    (gdb) break __sanitizer::Die
    (gdb) run crash-da39a3ee5e6b4b0d3255bfef95601890afd80709
    ...
    Thread 1 "ft.t" hit Breakpoint 1, __sanitizer::Die ()
    ...
    (gdb) where
    ...
    #4  0x0000000000539e25 in LLVMFuzzerTestOneInput (f=0x7fffffffc830)
    at ft.t.cpp:1
    ...

