// bdeflag_place.t.cpp                                                -*-C++-*-

#include <bdeflag_place.h>

#include <bdeflag_lines.h>
#include <bdeflag_ut.h>

#include <bslma_default.h>
#include <bslma_defaultallocatorguard.h>
#include <bslma_testallocator.h>

#include <bsl_iostream.h>
#include <bsl_string.h>

using namespace BloombergLP;
using namespace bdeFlag;

using bsl::cout;
using bsl::cerr;
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

//===================

const bsl::string dummyFileString1 =
"class Woof : Arf<This, That>, Meow {\n"                                //  1
"    // TYPES\n"                                                        //  2
"    typedef long long MyInt;\n"                                        //  3
"\n"                                                                    //  4
"    // DATA\n"                                                         //  5
"    int d_timesToBark;        // how many times to bark\n"             //  6
"\n"                                                                    //  7
"    // CLASS METHODS\n"                                                //  8
"    void woofWoof(int a, int b, int c);\n"                             //  9
"        // bark twice\n"                                               // 10
"\n"                                                                    // 11
"    // CREATORS\n"                                                     // 12
"    Woof(int timesToBark);\n"                                          // 13
"        // Create a Woof object initiailzed to barking\n"              // 14
"        // 'timesToBark' times.\n"                                     // 15
"\n"                                                                    // 16
"    if (woofWoof(3, 4, 12345678) * 12345678 +\n"                       // 17
"       (((47 * 34 >> 1) + 87654321)\n"                                 // 18
"             << 3) + woofWoof(\"asrf\"o, 12345678, 4)) {\n"            // 19
"        a = 4;\n"                                                      // 20
"    }\n"                                                               // 21
"\n"                                                                    // 22
"\n"                                                                    // 23
"    // ACCESSORS\n"                                                    // 24
"    int timesToBark();\n"                                              // 25
"\n"                                                                    // 26
"};\n"                                                                  // 27
"\n"                                                                    // 28
"//=================================================================\n" // 29
"//                         INLINE FUNCTIONS\n"                         // 30
"//=================================================================\n" // 31
"\n"                                                                    // 32
"// FREE OPERATORS\n"                                                   // 33
"bool operator==(const Woof& lhs, const Woof& rhs)\n"                   // 34
"{\n"                                                                   // 35
"    return lhs.timesToBark() == rhs.timesToBark();\n"                  // 36
"}\n"                                                                   // 37
"\n"                                                                    // 38
"bool arf<woof>(const Woof& lhs, const Woof& rhs)\n"                    // 39
"{\n"                                                                   // 40
"    return !(lhs == rhs);\n"                                           // 41
"}\n"                                                                   // 42
"\n"                                                                    // 43
"// CREATORS\n"                                                         // 44
"inline\n"                                                              // 45
"Woof::Woof(int timesToBark)\n"                                         // 46
": d_timesToBark(timesToBark)\n"                                        // 47
"{}\n"                                                                  // 48
"\n"                                                                    // 49
"inline\n"                                                              // 50
"int Woof::run(int i)\n"                                                // 51
"{\n"                                                                   // 52
"    for (int j = 0; j < i; ++j) {\n"                                   // 53
"       for (int k = 0; k < 4; ++k) {\n"                                // 54
"           rotateClockwise90();\n"                                     // 55
"       }\n"                                                            // 56
"    }\n"                                                               // 57
"}\n"                                                                   // 58
"\n"                                                                    // 59
"// ---------------------------------------------------------------\n"  // 60
"// NOTICE:\n"                                                          // 61
"//      Copyright (C) Bloomberg L.P., 2010\n"                          // 62
"//      All Rights Reserved.\n"                                        // 63
"//      Property of Bloomberg L.P.  (BLP)\n"                           // 64
"//      This software is made available solely pursuant to the\n"      // 65
"//      terms of a BLP license agreement which governs its use.\n"     // 66
"// ----------------------------- END-OF-FILE ---------------------\n"; // 67

const bsl::string templateFileString1 =
"template <arf>\n"                                                      //  1
"struct Woof;\n"                                                        //  2
"\n"                                                                    //  3
"template meow<class TYPE1,\n"                                          //  4
"             class TYPE2 = TYPE3, class TYPE4 = TYPE 5>\n"             //  5
"struct Woof2 {\n"                                                      //  6
"    int d_arf;\n"                                                      //  7
"    int d_meow;\n"                                                     //  8
"};\n";                                                                 //  9

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
      case 7: {
        // --------------------------------------------------------------------
        // TEST TEMPLATENAMEAFTER
        // --------------------------------------------------------------------

        const int EL = 10;      // End Line

        const struct {
            int         d_line;
            int         d_initLine;
            int         d_initCol;
            char        d_initChar;

            int         d_endLine;
            int         d_endCol;
            char        d_endChar;

            const char *d_wordAfter;
        } DATA[] = {
            { L_,  0,  0,   0,  1,  0, 't', "" },
            { L_, EL,  0,   0, EL,  0,   0, "" },
            { L_, EL, -9,   0, EL,  0,   0, "" },
            { L_, EL, -9,   0, EL,  0,   0, "" },
            { L_, EL, 10,   0, EL,  0,   0, "" },
            { L_, 99,  0,   0, EL,  0,   0, "" },
            { L_, 99, -9,   0, EL,  0,   0, "" },
            { L_, 99, 10,   0, EL,  0,   0, "" },
            { L_,  2,  6, ' ',  2,  7, 'W', "" },
            { L_,  1,  8, ' ',  1, 13, '>', "<arf>" },
            { L_,  1,  9, '<',  1, 13, '>', "<arf>" },
            { L_,  4,  8, ' ',  5, 54, '>', "meow<class TYPE1,"
                   "             class TYPE2 = TYPE3, class TYPE4 = TYPE 5>" },
            { L_,  4,  7, 'e',  4,  7, 'e', "" },
            { L_,  4,  9, 'm',  5, 54, '>', "meow<class TYPE1,"
                   "             class TYPE2 = TYPE3, class TYPE4 = TYPE 5>" },
            { L_,  4, 13, '<',  5, 54, '>', "<class TYPE1,"
                   "             class TYPE2 = TYPE3, class TYPE4 = TYPE 5>" },
        };

        enum { NUM_DATA = sizeof DATA / sizeof *DATA };

        Lines lines(templateFileString1);
        Place::setEnds();

        for (int i = 0; i < NUM_DATA; ++i) {
            const int LINE            = DATA[i].d_line;
            const int INITLINE        = DATA[i].d_initLine;
            const int INITCOL         = DATA[i].d_initCol;
            const char INITCHAR       = DATA[i].d_initChar;

            const int ENDLINE         = DATA[i].d_endLine;
            const int ENDCOL          = DATA[i].d_endCol;
            const int ENDCHAR         = DATA[i].d_endChar;

            const char *EXPWORDAFTER  = DATA[i].d_wordAfter;

            const Place INITPLACE(INITLINE, INITCOL);
            LOOP3_ASSERT(LINE, INITCHAR, *INITPLACE, INITCHAR == *INITPLACE);

            const bsl::string WORDAFTER_A = INITPLACE.templateNameAfter();
            LOOP3_ASSERT(LINE, EXPWORDAFTER, WORDAFTER_A,
                                                  EXPWORDAFTER == WORDAFTER_A);

            const Place EXPENDPLACE(ENDLINE, ENDCOL);
            LOOP3_ASSERT(LINE, ENDCHAR, *EXPENDPLACE, ENDCHAR == *EXPENDPLACE);

            Place endPlace;
            const bsl::string WORDAFTER_B =
                                        INITPLACE.templateNameAfter(&endPlace);
            LOOP3_ASSERT(LINE, EXPWORDAFTER, WORDAFTER_B,
                                                  EXPWORDAFTER == WORDAFTER_B);
            LOOP3_ASSERT(LINE, EXPENDPLACE, endPlace, EXPENDPLACE == endPlace);
        }
      }  break;
      case 6: {
        // --------------------------------------------------------------------
        // TEST TEMPLATENAMEBEFORE
        // --------------------------------------------------------------------

        static const struct {
            int         d_line;
            int         d_initLine;
            int         d_initCol;
            char        d_initChar;

            int         d_startLine;
            int         d_startCol;
            char        d_startChar;

            const char *d_wordBefore;
        } DATA[] = {
            { L_,  0,  0,   0,  0,  0,   0, "" },
            { L_, 68,  0,   0, 58,  0, '}', "" },
            { L_, 68, -9,   0, 58,  0, '}', "" },
            { L_, 68, -9,   0, 58,  0, '}', "" },
            { L_, 68, 10,   0, 58,  0, '}', "" },
            { L_, 78,  0,   0, 58,  0, '}', "" },
            { L_, 78, -9,   0, 58,  0, '}', "" },
            { L_, 78, 10,   0, 58,  0, '}', "" },
            { L_, 34,  4, ' ', 34,  3, 'l', "" },
            { L_, 34,  3, 'l', 34,  3, 'l', "" },
            { L_, 34,  2, 'o', 34,  2, 'o', "" },
            { L_, 46,  9, 'f', 46,  9, 'f', "" },
            { L_, 49,  0,   0, 48,  1, '}', "" },
            { L_, 41,  3, ' ', 40,  0, '{', "" },
            { L_, 51, 12, 'n', 51, 12, 'n', "" },
            { L_, 53,  8, '(', 53,  8, '(', "" },
            { L_, 39, 13, '>', 39,  5, 'a', "arf<woof>" },
        };

        enum { NUM_DATA = sizeof DATA / sizeof *DATA };

        Lines lines(dummyFileString1);
        Place::setEnds();

        for (int i = 0; i < NUM_DATA; ++i) {
            const int LINE            = DATA[i].d_line;
            const int INITLINE        = DATA[i].d_initLine;
            const int INITCOL         = DATA[i].d_initCol;
            const char INITCHAR       = DATA[i].d_initChar;

            const int STARTLINE       = DATA[i].d_startLine;
            const int STARTCOL        = DATA[i].d_startCol;
            const int STARTCHAR       = DATA[i].d_startChar;

            const char *EXPWORDBEFORE = DATA[i].d_wordBefore;

            const Place INITPLACE(INITLINE, INITCOL);
            LOOP3_ASSERT(LINE, INITCHAR, *INITPLACE, INITCHAR == *INITPLACE);

            const bsl::string WORDBEFORE_A = INITPLACE.templateNameBefore();
            LOOP3_ASSERT(LINE, EXPWORDBEFORE, WORDBEFORE_A,
                                                EXPWORDBEFORE == WORDBEFORE_A);

            const Place EXPSTARTPLACE(STARTLINE, STARTCOL);
            LOOP3_ASSERT(LINE, STARTCHAR, *EXPSTARTPLACE,
                                                  STARTCHAR == *EXPSTARTPLACE);

            Place startPlace;
            const bsl::string WORDBEFORE_B =
                                     INITPLACE.templateNameBefore(&startPlace);
            LOOP3_ASSERT(LINE, EXPWORDBEFORE, WORDBEFORE_B,
                                                EXPWORDBEFORE == WORDBEFORE_B);
            LOOP3_ASSERT(LINE, EXPSTARTPLACE, startPlace,
                                                  EXPSTARTPLACE == startPlace);
        }
      }  break;
      case 5: {
        // --------------------------------------------------------------------
        // TEST WORDBEFORE
        // --------------------------------------------------------------------

        static const struct {
            int         d_line;
            int         d_initLine;
            int         d_initCol;
            char        d_initChar;

            int         d_startLine;
            int         d_startCol;
            char        d_startChar;

            const char *d_wordBefore;
        } DATA[] = {
            { L_,  0,  0,   0,  0,  0,   0, "" },
            { L_, 68,  0,   0, 58,  0, '}', "" },
            { L_, 68, -9,   0, 58,  0, '}', "" },
            { L_, 68, -9,   0, 58,  0, '}', "" },
            { L_, 68, 10,   0, 58,  0, '}', "" },
            { L_, 78,  0,   0, 58,  0, '}', "" },
            { L_, 78, -9,   0, 58,  0, '}', "" },
            { L_, 78, 10,   0, 58,  0, '}', "" },
            { L_, 34,  4, ' ', 34,  0, 'b', "bool" },
            { L_, 34,  3, 'l', 34,  0, 'b', "bool" },
            { L_, 34,  2, 'o', 34,  0, 'b', "boo" },
            { L_, 46,  9, 'f', 46,  0, 'W', "Woof::Woof" },
            { L_, 49,  0,   0, 48,  1, '}', "" },
            { L_, 41,  3, ' ', 40,  0, '{', "" },
            { L_, 51, 12, 'n', 51,  4, 'W', "Woof::run" },
            { L_, 53,  8, '(', 53,  8, '(', "" },
        };

        enum { NUM_DATA = sizeof DATA / sizeof *DATA };

        Lines lines(dummyFileString1);
        Place::setEnds();

        for (int i = 0; i < NUM_DATA; ++i) {
            const int LINE            = DATA[i].d_line;
            const int INITLINE        = DATA[i].d_initLine;
            const int INITCOL         = DATA[i].d_initCol;
            const char INITCHAR       = DATA[i].d_initChar;

            const int STARTLINE       = DATA[i].d_startLine;
            const int STARTCOL        = DATA[i].d_startCol;
            const int STARTCHAR       = DATA[i].d_startChar;

            const char *EXPWORDBEFORE = DATA[i].d_wordBefore;

            const Place INITPLACE(INITLINE, INITCOL);
            LOOP3_ASSERT(LINE, INITCHAR, *INITPLACE, INITCHAR == *INITPLACE);

            const bsl::string WORDBEFORE_A = INITPLACE.wordBefore();
            LOOP3_ASSERT(LINE, EXPWORDBEFORE, WORDBEFORE_A,
                                                EXPWORDBEFORE == WORDBEFORE_A);

            const Place EXPSTARTPLACE(STARTLINE, STARTCOL);
            LOOP3_ASSERT(LINE, STARTCHAR, *EXPSTARTPLACE,
                                                  STARTCHAR == *EXPSTARTPLACE);

            Place startPlace;
            const bsl::string WORDBEFORE_B = INITPLACE.wordBefore(&startPlace);
            LOOP3_ASSERT(LINE, EXPWORDBEFORE, WORDBEFORE_B,
                                                EXPWORDBEFORE == WORDBEFORE_B);
            LOOP3_ASSERT(LINE, EXPSTARTPLACE, startPlace,
                                                  EXPSTARTPLACE == startPlace);
        }
      }  break;
      case 4: {
        // --------------------------------------------------------------------
        // TEST FINDSTATEMENTSTART
        // --------------------------------------------------------------------

        static const struct {
            int         d_line;
            int         d_initLine;
            int         d_initCol;
            char        d_initChar;

            int         d_startLine;
            int         d_startCol;
            char        d_startChar;
        } DATA[] = {
            { L_,  0,  0,   0,   0,  0,   0 },
            { L_,  0, 10,   0,   0,  0,   0 },
            { L_, -9,  0,   0,   0,  0,   0 },
            { L_,  0, -9,   0,   0,  0,   0 },
            { L_, -9, -9,   0,   0,  0,   0 },
            { L_, -9, 10,   0,   0,  0,   0 },

            { L_, 68,  0,   0,  58,  0, '}' },
            { L_, 68, 10,   0,  58,  0, '}' },
            { L_, 68, -9,   0,  58,  0, '}' },
            { L_, 78,  0,   0,  58,  0, '}' },
            { L_, 78, 10,   0,  58,  0, '}' },
            { L_, 78, -9,   0,  58,  0, '}' },

            { L_,  1,  0, 'c',   1,  0, 'c' },
            { L_,  1, 32, 'o',   1,  0, 'c' },
            { L_,  4,  0,   0,   4,  0,   0 },
            { L_,  3,  4, 't',   3,  4, 't' },
            { L_, 19, 16, '3',  17,  4, 'i' },
            { L_, 19, 46, '8',  17,  4, 'i' },
            { L_, 20, 12, '4',  20,  8, 'a' },
            { L_, 20,  8, 'a',  20,  8, 'a' },
            { L_, 21,  4, '}',  21,  4, '}' },
        };

        enum { NUM_DATA = sizeof DATA / sizeof *DATA };

        Lines lines(dummyFileString1);
        Place::setEnds();

        for (int i = 0; i < NUM_DATA; ++i) {
            const int LINE          = DATA[i].d_line;
            const int INITLINE      = DATA[i].d_initLine;
            const int INITCOL       = DATA[i].d_initCol;
            const char INITCHAR     = DATA[i].d_initChar;

            const int STARTLINE     = DATA[i].d_startLine;
            const int STARTCOL      = DATA[i].d_startCol;
            const char STARTCHAR    = DATA[i].d_startChar;

            if (veryVerbose) {
                cout << "LINE: " << LINE << endl;
            }

            const Place INITPLACE(INITLINE, INITCOL);
            LOOP3_ASSERT(LINE, INITCHAR, *INITPLACE, INITCHAR == *INITPLACE);

            const Place EXPSTARTPLACE(STARTLINE, STARTCOL);
            LOOP3_ASSERT(LINE, STARTCHAR, *EXPSTARTPLACE,
                                                  STARTCHAR == *EXPSTARTPLACE);
            const Place STARTPLACE = INITPLACE.findStatementStart();
            LOOP3_ASSERT(LINE, EXPSTARTPLACE, STARTPLACE,
                                                  EXPSTARTPLACE == STARTPLACE);
        }
      }  break;
      case 3: {
        // --------------------------------------------------------------------
        // FINDFIRSTOF, FINDFIRSTOFNOT TEST
        //
        // Concerns:
        //   Does findFirstOf function properly?
        //
        // Plan:
        //   Load the dummy file, set up Places, do findFirstOf, verify
        //   results.
        // --------------------------------------------------------------------

        static const struct {
            int         d_line;
            int         d_initLine;
            int         d_initCol;
            char        d_initChar;

            const char *d_toFind;

            int         d_foundLine;
            int         d_foundCol;
            char        d_foundChar;

            int         d_foundNotLine;
            int         d_foundNotCol;
            int         d_foundNotChar;
        } DATA[] = {
            { L_,  0,  0,   0, "Ar<:",   1, 11, ':',   1,  0, 'c' },
            { L_,  0,  0,   0, "({})",   1, 35, '{',   1,  0, 'c' },
            { L_,  0, -8,   0, "({})",   1, 35, '{',   1,  0, 'c' },
            { L_, -5,  0,   0, "({})",   1, 35, '{',   1,  0, 'c' },
            { L_, -5, -8,   0, "({})",   1, 35, '{',   1,  0, 'c' },

            { L_,  3,  0, ' ', "lMI",    3, 12, 'l',   3,  0, ' ' },
            { L_,  4,  0,   0, "Wy(",    9, 13, 'W',   6,  4, 'i' },
            { L_,  3,  5, 'y', "Why",    3,  5, 'y',   3,  6, 'p' },
            { L_,  3,  5, 'y', "(){}",   9, 17, '(',   3,  5, 'y' },

            { L_, 68,  0,   0, "Ar<:",  68,  0,   0,  68,  0,   0 },
            { L_, 68,  8,   0, "Ar<:",  68,  0,   0,  68,  0,   0 },
            { L_, 68, -8,   0, "Ar<:",  68,  0,   0,  68,  0,   0 },
            { L_, 80,  0,   0, "Ar<:",  68,  0,   0,  68,  0,   0 },
            { L_, 80,  8,   0, "Ar<:",  68,  0,   0,  68,  0,   0 },
            { L_, 80, -8,   0, "Ar<:",  68,  0,   0,  68,  0,   0 },
        };

        enum { NUM_DATA = sizeof DATA / sizeof *DATA };

        Lines lines(dummyFileString1);
        Place::setEnds();

        for (int i = 0; i < NUM_DATA; ++i) {
            const int LINE          = DATA[i].d_line;
            const int INITLINE      = DATA[i].d_initLine;
            const int INITCOL       = DATA[i].d_initCol;
            const char INITCHAR     = DATA[i].d_initChar;

            const char * TOFIND      = DATA[i].d_toFind;

            const int FOUNDLINE     = DATA[i].d_foundLine;
            const int FOUNDCOL      = DATA[i].d_foundCol;
            const char FOUNDCHAR    = DATA[i].d_foundChar;

            const int FOUNDNOTLINE  = DATA[i].d_foundNotLine;
            const int FOUNDNOTCOL   = DATA[i].d_foundNotCol;
            const char FOUNDNOTCHAR = DATA[i].d_foundNotChar;

            const Place INITPLACE(INITLINE, INITCOL);
            LOOP3_ASSERT(LINE, INITCHAR, *INITPLACE, INITCHAR == *INITPLACE);

            const Place FOUND = INITPLACE.findFirstOf(TOFIND);
            LOOP3_ASSERT(LINE, FOUNDCHAR, *FOUND, FOUNDCHAR == *FOUND);
            const Place EXPFOUND(FOUNDLINE, FOUNDCOL);
            LOOP3_ASSERT(LINE, EXPFOUND, FOUND, EXPFOUND == FOUND);

            const Place FOUNDNOT = INITPLACE.findFirstOf(TOFIND, false);
            LOOP3_ASSERT(LINE, FOUNDNOTCHAR, *FOUNDNOT,
                                                    FOUNDNOTCHAR == *FOUNDNOT);
            const Place EXPFOUNDNOT(FOUNDNOTLINE, FOUNDNOTCOL);
            LOOP3_ASSERT(LINE, EXPFOUNDNOT, FOUNDNOT, EXPFOUNDNOT == FOUNDNOT);
        }
      }  break;
      case 2: {
        // --------------------------------------------------------------------
        // ADD, SUBTRACT TEST
        //
        // Concerns:
        //   Do +, - operations on Places get the right result?
        //
        // Plan:
        //   Load the dummy file, set up Places, and & subtract from them,
        //   verify results.
        // --------------------------------------------------------------------

        static const struct {
            int         d_line;
            int         d_initLine;
            int         d_initCol;
            char        d_initChar;
            int         d_addBy;
            int         d_addLine;
            int         d_addCol;
            char        d_addChar;
            int         d_subBy;
            int         d_subLine;
            int         d_subCol;
            char        d_subChar;
        } DATA[] = {
            { L_,  0,  0,   0,    1,  1,  0, 'c',    1,  0,  0,   0 },
            { L_,  3,  0, ' ',    1,  3,  4, 't',    1,  1, 35, '{' },
            { L_, 68,  0,   0,    1, 68,  0,   0,    1, 58,  0, '}' },
            { L_, 54,  9, 'r',    1, 54, 11, '(',    1, 54,  8, 'o' },
            { L_, 54, 11, '(',    1, 54, 12, 'i',    1, 54,  9, 'r' },
            { L_, 52,  0, '{',    1, 53,  4, 'f',    1, 51, 19, ')' },
            { L_, 50,  1, 'n',    1, 50,  2, 'l',    1, 50,  0, 'i' },
            { L_, 48,  1, '}',    1, 50,  0, 'i',    1, 48,  0, '{' },
            { L_, 99, 83,   0,    1, 68,  0,   0,    1, 58,  0, '}' },
            { L_, -9, 26,   0,    1,  1,  0, 'c',    1,  0,  0,   0 },
            { L_, 99, -9,   0,    1, 68,  0,   0,    1, 58,  0, '}' },
            { L_, -9, -9,   0,    1,  1,  0, 'c',    1,  0,  0,   0 },

            { L_,  0,  0,   0,    5,  1,  4, 's',    7,  0,  0,   0 },
            { L_,  3,  0, ' ',   11,  3, 15, 'g',    7,  1, 27, '>' },
            { L_, 68,  0,   0,   23, 68,  0,   0,    6, 55, 28, '(' },
            { L_, 54,  9, 'r',    4, 54, 14, 't',    4, 53, 30, ')' },
            { L_, 54, 11, '(',    3, 54, 14, 't',    3, 54,  7, 'f' },
            { L_, 52,  0, '{',    4, 53,  8, '(',   18, 51,  0, 'i' },
            { L_, 50,  1, 'n',   24, 53,  4, 'f',    2, 48,  1, '}' },
            { L_, 48,  1, '}',    2, 50,  1, 'n',    3, 47, 26, 'k' },
            { L_, 99, 83,   0,   20, 68,  0,   0,    7, 55, 27, '0' },
            { L_, -9, 26,   0,    6,  1,  6, 'W',    7,  0,  0,   0 },
            { L_, 99, -9,   0,   20, 68,  0,   0,    7, 55, 27, '0' },
            { L_, -9, -9,   0,    6,  1,  6, 'W',    7,  0,  0,   0 },
        };

        enum { NUM_DATA = sizeof DATA / sizeof *DATA };

        Lines lines(dummyFileString1);
        Place::setEnds();

        for (int i = 0; i < NUM_DATA; ++i) {
            const int LINE      = DATA[i].d_line;
            const int INITLINE  = DATA[i].d_initLine;
            const int INITCOL   = DATA[i].d_initCol;
            const char INITCHAR = DATA[i].d_initChar;
            const int ADDBY     = DATA[i].d_addBy;
            const int ADDLINE   = DATA[i].d_addLine;
            const int ADDCOL    = DATA[i].d_addCol;
            const char ADDCHAR  = DATA[i].d_addChar;
            const int SUBBY     = DATA[i].d_subBy;
            const int SUBLINE   = DATA[i].d_subLine;
            const int SUBCOL    = DATA[i].d_subCol;
            const char SUBCHAR  = DATA[i].d_subChar;

            const Place INITPLACE(INITLINE, INITCOL);
            LOOP4_ASSERT(LINE, INITPLACE, INITCHAR, *INITPLACE,
                                                       INITCHAR == *INITPLACE);

            const Place ADDDEST = INITPLACE + ADDBY;
            const Place ADDEXP(ADDLINE, ADDCOL);
            LOOP3_ASSERT(LINE, ADDCHAR, *ADDDEST, ADDCHAR == *ADDDEST);
            LOOP3_ASSERT(LINE, ADDEXP,   ADDDEST, ADDEXP  ==  ADDDEST);

            const Place SUBDEST = INITPLACE - SUBBY;
            const Place SUBEXP(SUBLINE, SUBCOL);
            LOOP3_ASSERT(LINE, SUBCHAR, *SUBDEST, SUBCHAR == *SUBDEST);
            LOOP3_ASSERT(LINE, SUBEXP,   SUBDEST, SUBEXP  ==  SUBDEST);
        }
      }  break;
      case 1: {
        // --------------------------------------------------------------------
        // INCREMENT, DECREMENT TEST
        //
        // Concerns:
        //   Do ++,-- operations on Places get the right result?
        //
        // Plan:
        //   Load the dummy file, set up Places, increment them, verify
        //   results.
        // --------------------------------------------------------------------

        static const struct {
            int         d_line;
            int         d_initLine;
            int         d_initCol;
            char        d_initChar;
            int         d_nextLine;
            int         d_nextCol;
            char        d_nextChar;
            int         d_prevLine;
            int         d_prevCol;
            char        d_prevChar;
        } DATA[] = {
            { L_,  0,  0,   0,  1,  0, 'c',  0,  0,   0 },
            { L_,  3,  0, ' ',  3,  4, 't',  1, 35, '{' },
            { L_, 68,  0,   0, 68,  0,   0, 58,  0, '}' },
            { L_, 54,  9, 'r', 54, 11, '(', 54,  8, 'o' },
            { L_, 54, 11, '(', 54, 12, 'i', 54,  9, 'r' },
            { L_, 52,  0, '{', 53,  4, 'f', 51, 19, ')' },
            { L_, 50,  1, 'n', 50,  2, 'l', 50,  0, 'i' },
            { L_, 48,  1, '}', 50,  0, 'i', 48,  0, '{' },
            { L_, 99, 83,   0, 68,  0,   0, 58,  0, '}' },
            { L_, -9, 26,   0,  1,  0, 'c',  0,  0,   0 },
            { L_, 99, -9,   0, 68,  0,   0, 58,  0, '}' },
            { L_, -9, -9,   0,  1,  0, 'c',  0,  0,   0 },
        };

        enum { NUM_DATA = sizeof DATA / sizeof *DATA };

        Lines lines(dummyFileString1);
        Place::setEnds();

        for (int i = 0; i < NUM_DATA; ++i) {
            const int LINE      = DATA[i].d_line;
            const int INITLINE  = DATA[i].d_initLine;
            const int INITCOL   = DATA[i].d_initCol;
            const char INITCHAR = DATA[i].d_initChar;
            const int NEXTLINE  = DATA[i].d_nextLine;
            const int NEXTCOL   = DATA[i].d_nextCol;
            const char NEXTCHAR = DATA[i].d_nextChar;
            const int PREVLINE  = DATA[i].d_prevLine;
            const int PREVCOL   = DATA[i].d_prevCol;
            const char PREVCHAR = DATA[i].d_prevChar;

            const Place INITPLACE(INITLINE, INITCOL);

            {
                Place place(INITPLACE);
                LOOP4_ASSERT(LINE, INITPLACE, INITCHAR, *place,
                                                           INITCHAR == *place);

                ++place;
                LOOP4_ASSERT(LINE, INITPLACE, NEXTCHAR, *place,
                                                           NEXTCHAR == *place);
                const Place NEXTDEST(NEXTLINE, NEXTCOL);
                LOOP4_ASSERT(LINE, INITPLACE, NEXTDEST, place,
                                                           NEXTDEST == place);
            }

            {
                Place place(INITPLACE);
                LOOP4_ASSERT(LINE, INITPLACE, INITCHAR, *place,
                                                           INITCHAR == *place);

                --place;
                LOOP4_ASSERT(LINE, INITPLACE, PREVCHAR, *place,
                                                           PREVCHAR == *place);
                const Place PREVDEST(PREVLINE, PREVCOL);
                LOOP4_ASSERT(LINE, INITPLACE, PREVDEST, place,
                                                           PREVDEST == place);
            }
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
