// bdeflag_componenttable.t.cpp                                       -*-C++-*-

#include <bdeflag_componenttable.h>

#include <bslma_default.h>
#include <bslma_defaultallocatorguard.h>
#include <bslma_testallocator.h>

#include <bsl_iostream.h>
#include <bsl_string.h>

using namespace BloombergLP;
using namespace bdeflag;

using bsl::cerr;
using bsl::cout;
using bsl::endl;

//=============================================================================
//                      STANDARD BDE ASSERT TEST MACRO
//-----------------------------------------------------------------------------

static int testStatus = 0;

static void aSsErT(int c, const char *s, int i)
{
    if (c) {
        bsl::cout << "Error " << __FILE__ << "(" << i << "): " << s
                  << "    (failed)" << bsl::endl;
        if (0 <= testStatus && testStatus <= 100) ++testStatus;
    }
}

#define ASSERT(X) { aSsErT(!(X), #X, __LINE__); }

//=============================================================================
//                  STANDARD BDE LOOP-ASSERT TEST MACROS
//-----------------------------------------------------------------------------
#define LOOP_ASSERT(I,X) { \
    if (!(X)) { bsl::cout << #I << ": " << I << "\n"; aSsErT(1, #X, __LINE__);\
             }}

#define LOOP2_ASSERT(I,J,X) { \
    if (!(X)) { bsl::cout << #I << ": " << I << "\t" << #J << ": " \
                          << J << "\n"; aSsErT(1, #X, __LINE__); } }

#define LOOP3_ASSERT(I,J,K,X) { \
    if (!(X)) { bsl::cout << #I << ": " << I << "\t" << #J << ": " << J \
                          << "\t" << #K << ": " << K << "\n"; \
                aSsErT(1, #X, __LINE__); } }

#define LOOP4_ASSERT(I,J,K,L,X) { \
    if (!(X)) { bsl::cout << #I << ": " << I << "\t" << #J << ": " << J \
                          << "\t" << #K << ": " << K << "\t" << #L << ": " \
                          << L << "\n"; \
                aSsErT(1, #X, __LINE__); } }

#define LOOP5_ASSERT(I,J,K,L,M,X) { \
   if (!(X)) { bsl::cout << #I << ": " << I << "\t" << #J << ": " << J \
                         << "\t" << #K << ": " << K << "\t" << #L << ": " \
                         << L << "\t" << #M << ": " << M << "\n"; \
               aSsErT(1, #X, __LINE__); } }

#define LOOP6_ASSERT(I,J,K,L,M,N,X) { \
   if (!(X)) { bsl::cout << #I << ": " << I << "\t" << #J << ": " << J \
                         << "\t" << #K << ": " << K << "\t" << #L << ": " \
                         << L << "\t" << #M << ": " << M << "\t" << #N \
                         << ": " << N << "\n"; \
               aSsErT(1, #X, __LINE__); } }

//=============================================================================
//                  SEMI-STANDARD TEST OUTPUT MACROS
//-----------------------------------------------------------------------------
#define P(X) (bsl::cout << #X " = " << (X) << bsl::endl, 0)
                                                 // Print identifier and value.
#define Q(X) bsl::cout << "<| " #X " |>" << bsl::endl;
                                                 // Quote identifier literally.
#define P_(X) bsl::cout << #X " = " << (X) << ", "<< bsl::flush;
                                                 // P(X) without '\n'
#define L_ __LINE__                              // current Line number
#define PS(X) bsl::cout << #X " = \n" << (X) << bsl::endl;
                                                 // Print identifier and value.
#define T_()  bsl::cout << "\t" << bsl::flush;   // Print a tab (w/o newline)

int main(int argc, char *argv[])
{
    int test = argc > 1 ? atoi(argv[1]) : 0;

    int verbose = argc > 2;
    int veryVerbose = argc > 3;
    int veryVeryVerbose = argc > 4;
    int veryVeryVeryVerbose = argc > 5;

    bslma_TestAllocator taDefault;
    bslma_DefaultAllocatorGuard guard(&taDefault);
    ASSERT(&taDefault == bslma_Default::defaultAllocator());

    cout << "TEST " << __FILE__ << " CASE " << test << endl;;

    switch (test) { case 0:  // Zero is always the leading case.
      case 1: {
        // --------------------------------------------------------------------
        // TESTING getComponentName
        // --------------------------------------------------------------------

        if (verbose) cout << "TESTING getComponentName\n"
                             "========================\n";

        static const struct {
            const int   d_line;
            const char *d_in;
            const char *d_expected;
        } DATA[] = {
            { L_, "woof.t.cpp",           "woof" },
            { L_, "/a/b.c/d",             "/a/b.c/d" },
            { L_, "/a/b.c/d.c",           "/a/b.c/d" },
            { L_, "a/b/c/woof.arf.m.cpp", "a/b/c/woof.arf" },
            { L_, "a/b.c/woof.h",         "a/b.c/woof" },
            { L_, "a/b.c/woof.c",         "a/b.c/woof" },
            { L_, "a/b.c/woof.cpp",       "a/b.c/woof" },
            { L_, "a/b.c/woof.t.cpp",     "a/b.c/woof" },
            { L_, "a/b.c/woof.m.cpp",     "a/b.c/woof" },
            { L_, "a/b.c/woof.",          "a/b.c/woof" },
            { L_, "a/b.c/woof",           "a/b.c/woof" } };

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE        = DATA[i].d_line;
            const bsl::string IN  = DATA[i].d_in;
            const bsl::string EXP = DATA[i].d_expected;

            bsl::string componentName;
            ComponentTable::getComponentName(&componentName, IN);
            LOOP3_ASSERT(LINE, EXP, componentName, EXP == componentName);
        }
      }  break;
      default: {
        cerr << "WARNING: CASE `" << test << "' NOT FOUND." << endl;
        testStatus = -1;
      }
    }

    if (testStatus > 0) {
        cerr << "Error, non-zero test status = " << testStatus << "." << endl;
    }
    return testStatus;
}

// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2012
//      All Rights Reserved.
//      Property of Bloomberg L.P.  (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------
