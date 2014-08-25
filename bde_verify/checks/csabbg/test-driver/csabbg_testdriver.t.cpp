// csabbg_testdriver.t.cpp                                            -*-C++-*-

#include <bsl_cstdlib.h>
#include <bsl_iostream.h>

using namespace BloombergLP;
using bsl::cout;
using bsl::cerr;
using bsl::endl;
using bsl::flush;

//=============================================================================
//                                  TEST PLAN
//-----------------------------------------------------------------------------
///                                  Overview
///                                  --------
// Primary Manipulators:
//: o void setF();
//
// Basic Accessors:
//: o int F() const;
//-----------------------------------------------------------------------------
// MANIPULATORS
// [  ] void setF();
// [ 2] void setG();
// ACCESSORS
// [ 5] int F() const;
//-----------------------------------------------------------------------------
// [  ] BREATHING TEST
// [  ] USAGE EXAMPLE

// ============================================================================
//                       STANDARD BDE ASSERT TEST MACRO
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
# define ASSERT(X) { aSsErT(!(X), #X, __LINE__); }

// ============================================================================
//                       STANDARD BDE TEST DRIVER MACROS
// ----------------------------------------------------------------------------

#define C_(X)   << #X << ": " << X << '\t'
#define A_(X,S) { if (!(X)) { cout S << endl; aSsErT(1, #X, __LINE__); } }
#define LOOP_ASSERT(I,X)            A_(X,C_(I))
#define LOOP2_ASSERT(I,J,X)         A_(X,C_(I)C_(J))
#define LOOP3_ASSERT(I,J,K,X)       A_(X,C_(I)C_(J)C_(K))
#define LOOP4_ASSERT(I,J,K,L,X)     A_(X,C_(I)C_(J)C_(K)C_(L))
#define LOOP5_ASSERT(I,J,K,L,M,X)   A_(X,C_(I)C_(J)C_(K)C_(L)C_(M))
#define LOOP6_ASSERT(I,J,K,L,M,N,X) A_(X,C_(I)C_(J)C_(K)C_(L)C_(M)C_(N))

//=============================================================================
//                  SEMI-STANDARD TEST OUTPUT MACROS
//-----------------------------------------------------------------------------

#define P(X) cout << #X " = " << (X) << endl; // Print identifier and value.
#define Q(X) cout << "<| " #X " |>" << endl;  // Quote identifier literally.
#define P_(X) cout << #X " = " << (X) << ", " << flush; // P(X) without '\n'
#define L_ __LINE__                           // current Line number
#define T_ cout << "\t" << flush;             // Print tab w/o newline

// ============================================================================
//                  NEGATIVE-TEST MACRO ABBREVIATIONS
// ----------------------------------------------------------------------------

#define ASSERT_FAIL BSLS_ASSERTTEST_ASSERT_FAIL
#define ASSERT_PASS BSLS_ASSERTTEST_ASSERT_PASS

// ============================================================================
//                  EXCEPTION TEST MACRO ABBREVIATIONS
// ----------------------------------------------------------------------------

#define EXCEPTION_COUNT bslmaExceptionCounter

// ============================================================================
//                     GLOBAL TYPEDEFS FOR TESTING
// ----------------------------------------------------------------------------

typedef int Obj;

// ============================================================================
//                            MAIN PROGRAM
// ----------------------------------------------------------------------------

int main(int argc, char *argv[])
{
    int test = argc > 1 ? bsl::atoi(argv[1]) : 0;
    int verbose = argc > 2;
    int veryVerbose = argc > 3;
    int veryVeryVerbose = argc > 4;
    int veryVeryVeryVerbose = argc > 5;

    printf("%s %i\n", "TEST " __FILE__ " CASE ", test);

    switch (test) { case 0:  // Zero is always the leading case.
      case 3: {
        // --------------------------------------------------------------------
        // USAGE EXAMPLE
        //
        // Concerns:
        //   The usage example provided in the component header file must
        //   compile, link, and run on all platforms as shown.
        //
        // Plan:
        //   Incorporate usage example from header into driver, remove leading
        //   comment characters, and replace 'assert' with 'ASSERT'.  The code
        //   has been incorporated both above and here, since it includes
        //   freestanding data objects, functions, and function templates. C-1
        //
        // Testing:
        //   USAGE EXAMPLE
        // --------------------------------------------------------------------

        if (verbose) {
            cout << "Usage Example" << endl
                 << "=============" << endl;
        }

        static volatile const bool b = false;

        // These should not complain, because usage example.
        for (; b; ) { }
        while (b)   { }
        do          { } while (b);

      } break;
      case 2: {
        // --------------------------------------------------------------------
        // 'f' AND "setf"
        //  Test the 'f' and 'setF' methods.
        //
        // Concerns:
        //
        // Plan:
        //
        // Testing:
        //   int F() const;
        //   int G() const;
        // --------------------------------------------------------------------

        if (verbose) {
            cout << "'f' AND 'setf'" << endl
                 << "==========" << endl;
        }
      } break;
      case 1: {
        // --------------------------------------------------------------------
        // BREATHING TEST
        //   This case exercises (but does not fully test) basic functionality.
        //
        // Concerns:
        //: 1 The class is sufficiently functional to enable comprehensive
        //:   testing in subsequent test cases.
        //
        // Plan:
        //
        // Testing:
        //   BREATHING TEST
        // --------------------------------------------------------------------

        if (verbose) cout << "BREATHING TEST" << endl
                          << "==============" << endl;

        extern int F();

        static volatile const bool b = false;

        // The following three triplets are the basic tests.

        // These should generate no complaint.
        for (; b; ) { if (veryVerbose) { cout << endl; } F(); }
        while (b)   { if (veryVerbose) { cout << endl; } F(); }
        do          { if (veryVerbose) { cout << endl; } F(); } while (b);

        // These should also not generate a complaint.
        if (veryVerbose) { for (; b; ) { F(); }            }
        if (veryVerbose) { while (b)   { F(); }            }
        if (veryVerbose) { do          { F(); } while (b); }

        // Complain about using "verbose" inside loops.
        for (; b; ) { if (verbose) { cout << endl; } F(); }
        while (b)   { if (verbose) { cout << endl; } F(); }
        do          { if (verbose) { cout << endl; } F(); } while (b);

        // Complain about no "very verbose" action in loops.
        for (; b; ) { F(); }
        while (b)   { F(); }
        do          { F(); } while (b);

        // Repeat the basic tests within a non-loop substatement.
        if (b) {
            // These should generate no complaint.
            for (; b; ) { if (veryVerbose) { cout << endl; } F(); }
            while (b)   { if (veryVerbose) { cout << endl; } F(); }
            do          { if (veryVerbose) { cout << endl; } F(); } while (b);

            // These should also not generate a complaint.
            if (veryVerbose) { for (; b; ) { F(); }            }
            if (veryVerbose) { while (b)   { F(); }            }
            if (veryVerbose) { do          { F(); } while (b); }

            // Complain about using "verbose" inside loops.
            for (; b; ) { if (verbose) { cout << endl; } F(); }
            while (b)   { if (verbose) { cout << endl; } F(); }
            do          { if (verbose) { cout << endl; } F(); } while (b);

            // Complain about no "very verbose" action in loops.
            for (; b; ) { F(); }
            while (b)   { F(); }
            do          { F(); } while (b);
        }

        // Repeat the basic tests within a loop substatement that has no direct
        // "very verbose" action.  Policy is not to complain about this.
        while (b) {
            // These should generate no complaint.
            for (; b; ) { if (veryVerbose) { cout << endl; } F(); }
            while (b)   { if (veryVerbose) { cout << endl; } F(); }
            do          { if (veryVerbose) { cout << endl; } F(); } while (b);

            // Complain about using "verbose" inside loops.
            for (; b; ) { if (verbose) { cout << endl; } F(); }
            while (b)   { if (verbose) { cout << endl; } F(); }
            do          { if (verbose) { cout << endl; } F(); } while (b);

            // Complain about no "very verbose" action in loops.
            for (; b; ) { F(); }
            while (b)   { F(); }
            do          { F(); } while (b);
        }

        // Repeat the basic tests within a loop substatement that has a direct
        // very verbose action.
        while (b) {
            if (veryVerbose) { cout << endl; F(); }

            // These should generate no complaint.
            for (; b; ) { if (veryVerbose) { cout << endl; } F(); }
            while (b)   { if (veryVerbose) { cout << endl; } F(); }
            do          { if (veryVerbose) { cout << endl; } F(); } while (b);

            // These should also not generate a complaint.
            if (veryVerbose) { for (; b; ) { }            F(); }
            if (veryVerbose) { while (b)   { }            F(); }
            if (veryVerbose) { do          { } while (b); F(); }

            // Complain about using "verbose" inside loops.
            for (; b; ) { if (verbose) { cout << endl; } F(); }
            while (b)   { if (verbose) { cout << endl; } F(); }
            do          { if (verbose) { cout << endl; } F(); } while (b);

            // Complain about no "very verbose" action in loops.
            for (; b; ) { F(); }
            while (b)   { F(); }
            do          { F(); } while (b);
        }
      } break;
      case -1: {
      } break;
      default: {
        bsl::cerr << "WARNING: CASE `" << test << "' NOT FOUND." << bsl::endl;
        // testStatus = -1;
      }
    }
    return testStatus ? testStatus : 0;
}

// ============================================================================
//                                 TEST CLASS
// ============================================================================
//
//@CLASSES:
//    joe : just a class : stuff
//    bsl::basic_nonesuch : not there::more stuff

#define x() x()
namespace BloombergLP
{
    struct joe {
        void setF();
        void setG();
        int F() const;
        int F();
        int G() const;
        joe();
        joe(int);
        ~joe();
        void x();
    };
}

// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2013
//      All Rights Reserved.
//      Property of Bloomberg L.P.  (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------
