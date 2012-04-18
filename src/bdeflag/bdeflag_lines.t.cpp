// bdeflag_lines.t.cpp                                                -*-C++-*-

#include <bdeflag_lines.h>

#include <bdeflag_ut.h>

#include <bslma_default.h>
#include <bslma_defaultallocatorguard.h>
#include <bslma_testallocator.h>

#include <bsl_iostream.h>
#include <bsl_string.h>

using namespace BloombergLP;
using namespace bdeflag;

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

static int countNewlines(const bsl::string& in)
{
    int ret = 0;
    size_t pos = 0;
    while (Ut::npos() != (pos = in.find('\n', pos))) {
        ++pos;
        ++ret;
    }
    return ret;
}

static void noNewLines(int callingLine)
{
    for (int i = 0; i < Lines::lineCount(); ++i) {
        size_t pos = Lines::line(i).find('\n');
        LOOP3_ASSERT(callingLine, i, pos, Ut::npos() == pos);
    }
}

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
        // TEST WIPEOUTMACROS
        // --------------------------------------------------------------------

        const bsl::string dummyFileString =
            "// dummyFileString.cpp                    -*-C++-*-\n"     //  1
            "#include \"dummyfilestring.h\"\n"                          //  2
            "\n"                                                        //  3
            "#define WOOF(argA, argB)    ((argA) * ((argB) >> 4))\n"    //  4

            "\n"                                                        //  5
            "// CREATORS\n"                                             //  6
            "dummyFileString::dummyFileString()\n"                      //  7
            "{\n"                                                       //  8
            "    d_woof = 5;\n"                                         //  9

            "}\n"                                                       // 10
            "\n"                                                        // 11
            "  #  if WOOF(4, 17) == 3 && \\\n"                          // 12
            "        WOOF(374, 84) > 2\n"                               // 13
            "    // MANIPULATORS\n"                                     // 14

            "\n"                                                        // 15
            "#define MYWOOF(arf) {                          \\\n"       // 16
            "    if ((arf) > 6) {                           \\\n"       // 17
            "       return (arf) * 3;              // RETURN\\\n"       // 18
            "    }\n"                                                   // 19

            "\n"                                                        // 20
            "\n"                                                        // 21
            "// ACCESSORS\n"                                            // 22
            "dummyFileString::arf()\n"                                  // 23
            "{\n"                                                       // 24

            "    return d_arf;                     // RETURN\n"         // 25
            "}\n"                                                       // 26
            "\n";                                                       // 27

        bool emptyStrings[] = { 1, 1, 1, 1, 1,  1, 1, 0, 0, 0,
                                0, 1, 1, 1, 1,  1, 1, 1, 1, 1,
                                1, 1, 1, 0, 0,  0, 0, 1 };

        const Lines::CommentType N = Lines::BDEFLAG_NONE;

        Lines::CommentType comments[] = {
            N, Lines::BDEFLAG_UNRECOGNIZED, N, N, N,
            N, Lines::BDEFLAG_CREATOR, N, N, N,
            N, N, N, N, Lines::BDEFLAG_MANIPULATOR,
            N, N, N, N, N,
            N, N, Lines::BDEFLAG_ACCESSOR, N, N,
            Lines::BDEFLAG_RETURN, N, N };

        enum {
            NUM_EMPTY_STRINGS = sizeof emptyStrings / sizeof *emptyStrings,
            NUM_COMMENTS      = sizeof comments / sizeof *comments
        };

        Lines lines(dummyFileString);

        ASSERT(NUM_EMPTY_STRINGS == Lines::lineCount());
        LOOP2_ASSERT(NUM_COMMENTS, Lines::lineCount(),
                                           NUM_COMMENTS == Lines::lineCount());

        for (int li = 0; li < NUM_EMPTY_STRINGS; ++li) {
            LOOP3_ASSERT(li, emptyStrings[li], Lines::lineLength(li),
                                   emptyStrings[li] == !Lines::lineLength(li));
            LOOP3_ASSERT(li, comments[li], Lines::comment(li),
                                           comments[li] == Lines::comment(li));
        }
      }  break;
      case 5: {
        // --------------------------------------------------------------------
        // TEST BINARY STATIC CHECKS
        // --------------------------------------------------------------------

        static const struct {
            int                 d_line;
            bool                d_hasTabs;
            bool                d_includesDoubleQuotes;
            bool                d_includesAssertH;
            bool                d_includesCassert;
            const char         *d_in;
        } DATA[] = {
            { L_, 1, 0, 0, 0, "\nwoof\t\nmeow\n" },
            { L_, 0, 1, 0, 0, "\n  #   include \"woof.h\"\n#include <w.h>" },
            { L_, 0, 1, 0, 0, "\n  #   include <woof.h>\n#include \"w.h\"" },
            { L_, 0, 1, 0, 0, "\n#include \"woof.h\"\n#include <w.h>\n" },
            { L_, 0, 1, 0, 0, "\n#include\"woof.h\"\n#include <w.h>\n" },
            { L_, 0, 0, 0, 0, "\n#include<woof.h>\n#include <w.h>\n "},
            { L_, 0, 0, 1, 0, "\n # include <assert.h>\n" },
            { L_, 0, 0, 1, 0, "\n#include<assert.h>\n" },
            { L_, 0, 0, 1, 0, "\n#include <assert.h>\n" },
            { L_, 0, 0, 0, 1, "\n#include <cassert>\n" },
            { L_, 0, 0, 0, 1, "\n#include<cassert>\n" },
            { L_, 0, 0, 0, 1, "\n#     include<cassert>\n" },
            { L_, 0, 0, 0, 1, "\n   #     include<cassert>\n" } };

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE             = DATA[i].d_line;
            const bool EXPTABS         = DATA[i].d_hasTabs;
            const bool EXPDOUBLEQUOTES = DATA[i].d_includesDoubleQuotes;
            const bool EXPASSERTH      = DATA[i].d_includesAssertH;
            const bool EXPCASSERT      = DATA[i].d_includesCassert;
            const bsl::string IN       = DATA[i].d_in;

            Lines lines(IN);

            LOOP_ASSERT(LINE, EXPTABS == Lines::hasTabs());
            LOOP_ASSERT(LINE, EXPDOUBLEQUOTES ==Lines::includesDoubleQuotes());
            LOOP_ASSERT(LINE, EXPASSERTH == Lines::includesAssertH());
            LOOP_ASSERT(LINE, EXPCASSERT == Lines::includesCassert());
        }
      }  break;
      case 4: {
        static const struct {
            int                 d_line;
            Lines::CommentType  d_comment;
            int                 d_expCommentLine;
            const char         *d_in;
        } DATA[] = {
            { L_, Lines::BDEFLAG_NOT_IMPLEMENTED, 2,
                                             "\n   woof; // NOT IMPLEMENTED" },
            { L_, Lines::BDEFLAG_MANIPULATOR,     2,
                                             "\n  // MANIPULATORS\n woof;\n" },
            { L_, Lines::BDEFLAG_CREATOR,         1,
                                                  " woof; // CREATORS\n\n\n" },
            { L_, Lines::BDEFLAG_MANIPULATOR,     2,
                                              "\n  // MANIPULATOR\n woof;\n" },
            { L_, Lines::BDEFLAG_CREATOR,         1," woof; // CREATOR\n\n\n"},
            { L_, Lines::BDEFLAG_ACCESSOR,        3,
                                                 "\n\nwoof; // ACCESSOR\n\n" },
            { L_, Lines::BDEFLAG_CLOSE_NAMESPACE, 1,
                                              "woof; // close namespace\n\n" },
            { L_, Lines::BDEFLAG_CLOSE_UNNAMED_NAMESPACE, 3,
                             "woof; \n\n}  // close unnamed namespace\n\n" },
            { L_, Lines::BDEFLAG_TYPE,         2, "\nwoof; // TYPEa\n" },
            { L_, Lines::BDEFLAG_CLASS_DATA,   2, "\nwoof; // CLASS DATA\n" },
            { L_, Lines::BDEFLAG_DATA,         2, "\nwoof; // DATA\n" },
            { L_, Lines::BDEFLAG_FRIEND,       2, "\nwoof; // FRIEND\n" },
            { L_, Lines::BDEFLAG_CLASS_METHOD,          2,
                                                       "\n// CLASS METHOD\n" },
            { L_, Lines::BDEFLAG_NOT_IMPLEMENTED,       2,
                                                    "\n// NOT IMPLEMENTED\n" },
            { L_, Lines::BDEFLAG_CREATOR,               2, "\n// CREATOR\n" },
            { L_, Lines::BDEFLAG_MANIPULATOR,           2,
                                                        "\n// MANIPULATOR\n" },
            { L_, Lines::BDEFLAG_ACCESSOR,              2, "\n// ACCESSOR\n" },
            { L_, Lines::BDEFLAG_FREE_OPERATOR,         2,
                                                      "\n// FREE OPERATOR\n" },
            { L_, Lines::BDEFLAG_CLOSE_NAMESPACE,       2,
                                                    "\n// close namespace\n" },
            { L_, Lines::BDEFLAG_CLOSE_UNNAMED_NAMESPACE,2,
                                            "\n// close unnamed namespace\n" },
            { L_, Lines::BDEFLAG_UNRECOGNIZED,        2, "\n   // woof\n\n" }};

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE                      = DATA[i].d_line;
            const Lines::CommentType EXPCOMMENT = DATA[i].d_comment;
            const int EXPCOMMENTLINE            = DATA[i].d_expCommentLine;
            const bsl::string IN                = DATA[i].d_in;

            Lines lines(IN);

            for (int li = 1; li < Lines::lineCount(); ++li) {
                if (Lines::BDEFLAG_NONE != Lines::comment(li)) {
                    LOOP_ASSERT(LINE, Lines::comment(li) == EXPCOMMENT);
                    LOOP3_ASSERT(LINE, EXPCOMMENTLINE, li,
                                                         EXPCOMMENTLINE == li);
                }
            }
        }
      }  break;
      case 3: {
        static const struct {
            int         d_line;
            const char *d_in;
            const bool  d_cStyleComments;
        } DATA[] = {
            { L_, "  woof\n  arf\n  meow\n",     false },
            { L_, "  /* wo */  arf\n  meow\n",   true  },
            { L_, "  /* wo **/  arf\n  meow\n",  true  },
            { L_, "  /* wo /*/  arf\n  meow\n",  true  },
            { L_, "  /* /* */  arf\n  meow\n",   true  },
            { L_, "  /* ///*/  arf\n  meow\n",   true  },
            { L_, "  /* wo **/  arf\n  ''''\n",  true  },
            { L_, "  /* wo /*/  arf\n  '\\n'\n", true  },
            { L_, "  /* /* */  arf\n'''''''\n",  true  },
            { L_, "  /* ///*/  arf\n  'a'm\n",   true  },
            { L_, "  \"/*\"\n",                  false },
            { L_, "  \"/*\"\nmeow",              false },
            { L_, "  \"wo\"\n",                  false },
            { L_, "  \"wo\"\nmeow",              false },
            { L_, "  \"//\"\n",                  false },
            { L_, "  \"//\"\nmeow",              false },
            { L_, "  //* wo */  arf\n  meow\n",  false },
            { L_, "  woof // arf\n  meow\n",     false },
            { L_, "  w // RETURNwoof\n  arf\n",  false },
            { L_, "  // MANIPULATORS\n  arf\n",  false },
            { L_, "  arf\nmeow",                 false },
            { L_, "/* */ arf\n",                 true  },
            { L_, "//  arf\n  meow\n",           false },
        };

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        Ut::LineNumSet isComment;
        isComment.insert(1);
        Ut::LineNumSet noComments;

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE            = DATA[i].d_line;
            const bsl::string IN      = DATA[i].d_in;
            const bool CSTYLECOMMENTS = DATA[i].d_cStyleComments;

            const Ut::LineNumSet& comments = CSTYLECOMMENTS
                                          ? isComment
                                          : noComments;

            Lines lines(IN);

            LOOP2_ASSERT(LINE, Lines::cStyleComments(),
                                          comments == Lines::cStyleComments());
        }
      }  break;
      case 2: {
        static const struct {
            int         d_line;
            const char *d_in;
            const char *d_exp;
        } DATA[] = {
            { L_, "  woof\n  arf\n  meow\n",    "  woof\n  arf\n  meow\n" },
            { L_, "  /* wo */  arf\n  meow\n",  "            arf\n  meow\n" },
            { L_, "  /* wo **/  arf\n  meow\n", "             arf\n  meow\n" },
            { L_, "  /* wo /*/  arf\n  meow\n", "             arf\n  meow\n" },
            { L_, "  /* /* */  arf\n  meow\n",  "            arf\n  meow\n" },
            { L_, "  /* ///*/  arf\n  meow\n",  "            arf\n  meow\n" },
            { L_, "  /* wo **/  arf\n  ''''\n", "             arf\n  ''''\n" },
            { L_, "  /* wo /*/  arf\n  '\\n'\n","             arf\n  ''''\n" },
            { L_, "  /* /* */  arf\n'''''''\n", "            arf\n'''''''\n" },
            { L_, "  /* ///*/  arf\n  'a'm\n",  "            arf\n  '''m\n" },
            { L_, "  \"/*\"\n",                 "  \"\"\"\"\n" },
            { L_, "  \"/*\"\nmeow",             "  \"\"\"\"\nmeow\n" },
            { L_, "  \"wo\"\n",                 "  \"\"\"\"\n" },
            { L_, "  \"wo\"\nmeow",             "  \"\"\"\"\nmeow\n" },
            { L_, "  \"//\"\n",                 "  \"\"\"\"\n" },
            { L_, "  \"//\"\nmeow",             "  \"\"\"\"\nmeow\n" },
            { L_, "  //* wo */  arf\n  meow\n", "\n  meow\n" },
            { L_, "  //         arf\n  meow\n", "\n  meow\n" },
            { L_, "  woof // arf\n  meow\n",    "  woof\n  meow\n" },
            { L_, "  w // RETURNwoof\n  arf\n", "  w\n  arf\n" },
            { L_, "  // MANIPULATORS\n  arf\n", "\n  arf\n" },
            { L_, "  arf\nmeow",                "  arf\nmeow\n" },
            { L_, "/* */ arf\n",                "      arf\n" },
            { L_, "//  arf\n  meow\n",          "\n  meow\n" },
        };

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        const Ut::LineNumSet noLongLines;

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE        = DATA[i].d_line;
            const bsl::string IN  = DATA[i].d_in;
            const bsl::string EXP = DATA[i].d_exp;

            Lines lines(IN);

            noNewLines(LINE);

            LOOP_ASSERT(LINE, noLongLines == Lines::longLines());

            LOOP_ASSERT(LINE, Lines::lineCount() == 1 + countNewlines(EXP));
            LOOP_ASSERT(LINE, "" == Lines::line(0));

            const bsl::string& result = Lines::asString();
            LOOP3_ASSERT(LINE, result, EXP, result == EXP);
        }
      }  break;
      case 1: {
        static const struct {
            int         d_line;
            const char *d_in;
            int         d_longs[3];
        } DATA[] = {
            { L_, "\n\n\n"
                  "1234567891123456789212345678931234567894"
                  "1234567895123456789612345678971234567898\n", { 4, 0, 0 } },
            { L_, "\n\n"
                  "1234567891123456789212345678931234567894"
                  "123456789512345678961234567897123456789\n"
                  "1234567891123456789212345678931234567894"
                  "1234567895123456789612345678971234567898\n", { 4, 0, 0 } },
            { L_, "\n\n"
                  "1234567891123456789212345678931234567894"
                  "123456789512345678961234567897123456789\n"
                  "1234567891123456789212345678931234567894"
                  "1234567895123456789612345678971234567898123\n"
                  "\n\n\n"
                  "1234567891123456789212345678931234567894"
                  "1234567895123456789612345678971234567898\n", { 4, 8, 0 } },
        };

        enum { DATA_LEN = sizeof DATA / sizeof *DATA };

        for (int i = 0; i < DATA_LEN; ++i) {
            const int LINE        = DATA[i].d_line;
            const bsl::string IN  = DATA[i].d_in;
            const int *longs      = DATA[i].d_longs;

            Lines lines(IN);

            noNewLines(LINE);

            Ut::LineNumSet longSet;
            for (int i = 0; i < 3; ++i) {
                if (0 == longs[i]) {
                    break;
                }

                longSet.insert(longs[i]);
            }

            LOOP_ASSERT(LINE, Lines::longLines() == longSet);
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
