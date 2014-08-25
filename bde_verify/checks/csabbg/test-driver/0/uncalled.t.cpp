#include <stdlib.h>
#include <bsl_iostream.h>

using namespace BloombergLP;
using namespace bsl;

//=============================================================================
//                             TEST PLAN
//-----------------------------------------------------------------------------
//                              Overview
//                              --------
// Nothing.
//-----------------------------------------------------------------------------
// [ 1] joe();
// [ 1] joe(int uncalled);
// [ 1] void f1();
// [ 1] void f1(int uncalled);
// [ 1] void f2();
// [ 1] void f2(int uncalled);
// [ 1] void f3();
// [ 1] void f3(int uncalled);
// [ 1] static void f4();
// [ 1] static void f4(int uncalled);
// [ 1] static void f5();
// [ 1] static void f5(int uncalled);
// [ 1] static void f6();
// [ 1] static void f6(int uncalled);
// [ 1] static void f7();
// [ 1] static void f7(int uncalled);
// [ 1] void f8(int uncalled);
// [ 1] static void f9(int uncalled);
//-----------------------------------------------------------------------------

// ============================================================================
//                      STANDARD BDE ASSERT TEST MACROS
// ----------------------------------------------------------------------------

static int testStatus = 0;

static void aSsErT(int c, const char *s, int i)
{
    if (c) {
        cout << "Error " << __FILE__ << "(" << i << "): " << s
             << "    (failed)" << endl;
        if (testStatus >= 0 && testStatus <= 100) ++testStatus;
    }
}

// ============================================================================
//                      STANDARD BDE TEST DRIVER MACROS
// ----------------------------------------------------------------------------

#define ASSERT       BDLS_TESTUTIL_ASSERT
#define LOOP_ASSERT  BDLS_TESTUTIL_LOOP_ASSERT
#define LOOP0_ASSERT BDLS_TESTUTIL_LOOP0_ASSERT
#define LOOP1_ASSERT BDLS_TESTUTIL_LOOP1_ASSERT
#define LOOP2_ASSERT BDLS_TESTUTIL_LOOP2_ASSERT
#define LOOP3_ASSERT BDLS_TESTUTIL_LOOP3_ASSERT
#define LOOP4_ASSERT BDLS_TESTUTIL_LOOP4_ASSERT
#define LOOP5_ASSERT BDLS_TESTUTIL_LOOP5_ASSERT
#define LOOP6_ASSERT BDLS_TESTUTIL_LOOP6_ASSERT
#define ASSERTV      BDLS_TESTUTIL_ASSERTV

#define Q   BDLS_TESTUTIL_Q   // Quote identifier literally.
#define P   BDLS_TESTUTIL_P   // Print identifier and value.
#define P_  BDLS_TESTUTIL_P_  // P(X) without '\n'.
#define T_  BDLS_TESTUTIL_T_  // Print a tab (w/o newline).
#define L_  BDLS_TESTUTIL_L_  // current Line number

//@CLASSES:
//    joe : just a class

namespace BloombergLP
{
    struct joe {
        joe();
        joe(int uncalled);
        void f1();
        void f1(int uncalled);
        void f2();
        void f2(int uncalled);
        void f3();
        void f3(int uncalled);
        static void f4();
        static void f4(int uncalled);
        static void f5();
        static void f5(int uncalled);
        static void f6();
        static void f6(int uncalled);
        static void f7();
        static void f7(int uncalled);
        void f8(int uncalled);
        static void f9(int uncalled);
    };
    void f8(int);
    void f9(int);
}

//=============================================================================
//                              MAIN PROGRAM
//-----------------------------------------------------------------------------

int main(int argc, char *argv[])
{
    int test     = argc > 1 ? atoi(argv[1]) : 0;
    bool verbose = argc > 2;

    switch (test) {
      case 1: {
        // --------------------------------------------------------------------
        // DETECT UNCALLED METHODS
        //
        // Concerns:
        //:  1 Bde_verify detects uncalled methods.
        //
        // Plan:
        //:  1 Don't call some methods.
        //:  2 See whether bde_verify notices.
        //:  3 ???
        //:  4 Profit!
        //
        // Testing:
        //   joe();
        //   joe(int uncalled);
        //   void f1();
        //   void f1(int uncalled);
        //   void f2();
        //   void f2(int uncalled);
        //   void f3();
        //   void f3(int uncalled);
        //   static void f4();
        //   static void f4(int uncalled);
        //   static void f5();
        //   static void f5(int uncalled);
        //   static void f6();
        //   static void f6(int uncalled);
        //   static void f7();
        //   static void f7(int uncalled);
        //   void f8(int uncalled);
        //   static void f9(int uncalled);
        // --------------------------------------------------------------------

        if (verbose) cout << endl
                          << "DETECT UNCALLED METHODS" << endl
                          << "=======================" << endl;

          joe j, &rj = j, *pj = &j;

          j.f1();
          rj.f2();
          pj->f3();
          joe::f4();
          j.f5();
          rj.f6();
          pj->f7();
          f8(0);
          f9(0);
      } break;
    }
    return testStatus;
}

// ----------------------------------------------------------------------------
// Copyright (C) 2014 Bloomberg Finance L.P.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
// ----------------------------- END-OF-FILE ----------------------------------
