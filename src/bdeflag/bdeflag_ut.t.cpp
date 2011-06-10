// bdeflag_ut.t.cpp                                                   -*-C++-*-

#include <bdeflag_ut.h>

#include <bslma_default.h>
#include <bslma_defaultallocatorguard.h>
#include <bslma_testallocator.h>

#include <bsl_iostream.h>
#include <bsl_string.h>

using namespace BloombergLP;
using namespace bdeFlag;

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
      case 6: {
        // --------------------------------------------------------------------
        // TESTING WORDBEFORE
        // --------------------------------------------------------------------

        static const struct {
            const int   d_line;
            const char *d_in;
            const int   d_start;
            const char *d_exp;
            const int   d_end;
        } DATA[] = {
            { L_, " abc ",               1, "abc",              3 },
            { L_, " abc ",               0, "abc",              3 },
            { L_, "woof::meow    ",      0, "woof::meow",       9 },
            { L_, " woof::meow    ",     1, "woof::meow",      10 },
            { L_, "    wo1f::m78w ",     4, "wo1f::m78w",      13 },
            { L_, "    wo1f::m78w ",     0, "wo1f::m78w",      13 },
            { L_, "               ",     7, "",                -1 },
            { L_, "       ;       ",     7, "",                 7 },
            { L_, "       )       ",     7, "",                 7 },
            { L_, "       {       ",     7, "",                 7 },
            { L_, "   abcd{abcd   ",     7, "",                 7 },
            { L_, "wo1f::m78w     ",     0, "wo1f::m78w",       9 },
            { L_, "wo1f::~m78w    ",     0, "wo1f::~m78w",     10 },
            { L_, "wo1f::m78w    a",     0, "wo1f::m78w",       9 } };

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE            = DATA[i].d_line;
            const bsl::string IN      = DATA[i].d_in;
            const int START           = DATA[i].d_start;
            const bsl::string EXP     = DATA[i].d_exp;
            const int EXPEND          = DATA[i].d_end;

            bsl::string nb = Ut::wordAfter(IN, START);
            LOOP3_ASSERT(LINE, EXP, nb, EXP == nb);
            int end;
            nb = Ut::wordAfter(IN, START, &end);
            LOOP3_ASSERT(LINE, EXP, nb, EXP == nb);
            LOOP3_ASSERT(LINE, EXPEND, end, EXPEND == end);
        }
      }  break;
      case 5: {
        // --------------------------------------------------------------------
        // TESTING WORDBEFORE
        // --------------------------------------------------------------------

        static const struct {
            const int   d_line;
            const char *d_in;
            const int   d_end;
            const char *d_exp;
            const int   d_start;
        } DATA[] = {
            { L_, " abc ",               4, "abc",              1 },
            { L_, " abc ",               3, "abc",              1 },
            { L_, "woof::meow    ",     13, "woof::meow",       0 },
            { L_, " woof::meow    ",    14, "woof::meow",       1 },
            { L_, "    wo1f::m78w ",    13, "wo1f::m78w",       4 },
            { L_, "    wo1f::m78w ",    12, "wo1f::m78",        4 },
            { L_, "               ",    12, "",                -1 },
            { L_, "       ;       ",    12, "",                 7 },
            { L_, "       )       ",    12, "",                 7 },
            { L_, "       {       ",    12, "",                 7 },
            { L_, "   abcd{abcd   ",     7, "",                 7 },
            { L_, "wo1f::m78w     ",    13, "wo1f::m78w",       0 },
            { L_, "wo1f::m78w     ",    13, "wo1f::m78w",       0 },
            { L_, "wo1f::~m78w    ",    13, "wo1f::~m78w",      0 },
            { L_, "wo1f::m78w    a",    13, "wo1f::m78w",       0 } };

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE            = DATA[i].d_line;
            const bsl::string IN      = DATA[i].d_in;
            const int END             = DATA[i].d_end;
            const bsl::string EXP     = DATA[i].d_exp;
            const int EXPSTART        = DATA[i].d_start;

            bsl::string nb = Ut::wordBefore(IN, END);
            LOOP3_ASSERT(LINE, EXP, nb, EXP == nb);
            int start;
            nb = Ut::wordBefore(IN, END, &start);
            LOOP3_ASSERT(LINE, EXP, nb, EXP == nb);
            LOOP3_ASSERT(LINE, EXPSTART, start, EXPSTART == start);
        }
      }  break;
      case 4: {
        // --------------------------------------------------------------------
        // TESTING FRONTMATCHES
        // --------------------------------------------------------------------

        static const struct {
            const int   d_line;
            const char *d_in;
            const char *d_pattern;
            const int   d_pos;
            const bool  d_exp;
        } DATA[] = {
            { L_, " abc ",         "bc",        2, 1 },
            { L_, "       abc ",   "abc ",     -1, 1 },
            { L_, "       abc ",   "bc",        8, 1 },
            { L_, "       abc ",   "bc",        7, 0 },
            { L_, "       abc ",   "bc",       -1, 0 } };

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE            = DATA[i].d_line;
            const bsl::string IN      = DATA[i].d_in;
            const bsl::string PATTERN = DATA[i].d_pattern;
            const int POS             = DATA[i].d_pos;
            const bool EXP            = DATA[i].d_exp;

            if (-1 == POS) {
                ASSERT(EXP == Ut::frontMatches(IN, PATTERN));
            }
            else {
                ASSERT(EXP == Ut::frontMatches(IN, PATTERN, POS));
            }
        }
      }  break;
      case 3: {
        // --------------------------------------------------------------------
        // TESTING CHARATORBEFORE
        // --------------------------------------------------------------------

        static const struct {
            const int   d_line;
            const char *d_in;
            const int   d_offset;    // offset from end of string
            const char  d_exp;
            const int   d_expAtCol;
        } DATA[] = {
            { L_, " abc ",              -3, 0,   -1 },
            { L_, " abc ",              10, 'c',  3 },
            { L_, " abc ",               3, 'c',  3 },
            { L_, " abc ",               2, 'b',  2 },
            { L_, "abc ",                0, 'a',  0 },
            { L_, "   abc ",             0, 0,   -1 },
            { L_, "   abc ",             2, 0,   -1 },
            { L_, "   abc ",             6, 'c',  5 },
            { L_, "   abc ",             5, 'c',  5 },
            { L_, "   abc ",             3, 'a',  3 } };

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE        = DATA[i].d_line;
            const bsl::string IN  = DATA[i].d_in;
            const int OFFSET      = DATA[i].d_offset;
            const char EXP        = DATA[i].d_exp;
            const int EXPATCOL    = DATA[i].d_expAtCol;

            int atCol;

            ASSERT(EXP == Ut::charAtOrBefore(IN, OFFSET));
            ASSERT(EXP == Ut::charAtOrBefore(IN, OFFSET, &atCol));

            if (-1 != EXPATCOL) {
                ASSERT(EXPATCOL == atCol);
            }
        }
      }  break;
      case 2: {
        // --------------------------------------------------------------------
        // TESTING FIRSTCHAROF
        // --------------------------------------------------------------------

        static const struct {
            const int   d_line;
            const char *d_in;
            const char  d_exp;
        } DATA[] = {
            { L_, "            arf", 'a' },
            { L_, "arf     ", 'a' },
            { L_, "      *arf ", '*' },
            { L_, "", 0 } };

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE        = DATA[i].d_line;
            const bsl::string IN  = DATA[i].d_in;
            const char EXP        = DATA[i].d_exp;

            LOOP_ASSERT(LINE, EXP == Ut::firstCharOf(IN));
        }
      }  break;
      case 1: {
        // --------------------------------------------------------------------
        // TESTING BLOCKOUTQUOTES
        // --------------------------------------------------------------------

        static const struct {
            const int   d_line;
            const char *d_in;
            const char *d_exp;
            const char  d_startsQuoted;
            const char  d_endsQuoted;
        } DATA[] = {
            { L_, "dkafjlfdajs\"fajkkfad\"afd",
                                  "dkafjlfdajs\"\"\"\"\"\"\"\"\"\"afd", 0, 0 },
            { L_, "'\\''",              "''''", 0, 0 },
            { L_, "asdf\"1234\\\"1234\"asdf",
                                    "asdf\"\"\"\"\"\"\"\"\"\"\"\"asdf", 0, 0 },
            { L_, "endMatches(woof, \"woof\")",
                                      "endMatches(woof, \"\"\"\"\"\")", 0, 0 },
            { L_, "dkafjlfdajs'fajkkfad'afd", "dkafjlfdajs''''''''''afd",
                                                                        0, 0 },
            { L_, "'\\''",              "''''", 0, 0 },
            { L_, "asdf'1234\\'1234'asdf", "asdf''''''''''''asdf", 0, 0 },
            { L_, "endMatches(woof, 'woof')", "endMatches(woof, '''''')",
                                                                        0, 0 },
            { L_, "end'Matches(woof, 'woof')", "''''Matches(woof, '''''')",
                                                                     '\'', 0 },
            { L_, "endMatches(woof, 'woof\\", "endMatches(woof, ''''''",
                                                                     0, '\'' },
            { L_, "woof\\", "\"\"\"\"\"", '"', '"' },
        };

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE          = DATA[i].d_line;
            const bsl::string IN    = DATA[i].d_in;
            const bsl::string EXP   = DATA[i].d_exp;
            const char STARTSQUOTED = DATA[i].d_startsQuoted;
            const char ENDSQUOTED   = DATA[i].d_endsQuoted;

            if (!STARTSQUOTED) {
                bsl::string result = IN;
                ASSERT(ENDSQUOTED == Ut::blockOutQuotes(&result));

                LOOP2_ASSERT(result, EXP, result == EXP);
            }

            bsl::string result = IN;
            ASSERT(ENDSQUOTED == Ut::blockOutQuotes(&result, STARTSQUOTED));

            LOOP2_ASSERT(result, EXP, result == EXP);
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
//      Copyright (C) Bloomberg L.P., 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P.  (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------
