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

A fuzz test is expected to crash on the first failure detected.  This might be
a "natural" crash, perhaps because the program indirects through bad pointers,
or a deliberate crash via an unhandled exception or a call to ``abort``.  In
BDE fuzz tests, a deliberate crash is invoked through the assertion system, as
seen below.

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
            the result if the method is correct.

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
of the ``clang`` compiler be used.

  ::

    $ eval `bde_build_env.py -t opt_exc_mt_64_asan_fuzz_cpp17 -c clang-10`

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

