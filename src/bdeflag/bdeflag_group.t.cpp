// bdeflag_group.t.cpp                                                -*-C++-*-

#include <bdeflag_group.h>

#include <bdeflag_lines.h>
#include <bdeflag_place.h>
#include <bdeflag_ut.h>

#include <bslma_default.h>
#include <bslma_defaultallocatorguard.h>
#include <bslma_testallocator.h>

#include <bsl_iostream.h>
#include <bsl_string.h>

#include <bsl_cstdio.h>

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
"#include <woof.h>\n"                                                   //  1
"\n"                                                                    //  2
"#include <assert.h>\n"                                                 //  3
"\n"                                                                    //  4
"namespace woof {\n"                                                    //  5
"#define WHOPPER(a) do {                                \\\n"           //  6
"               int b = 5 * (a);                        \\\n"           //  7
"               printf(\"5 * #a == %d\\n\"              \\\n"           //  8
"           } while (false)\n"                                          //  9
"\n"                                                                    // 10
"                       // ----------\n"                                // 11
"                       // class Woof\n"                                // 12
"                       // ----------\n"                                // 13
"\n"                                                                    // 14
"class Woof : Arf<This, That>, Meow {\n"                                // 15
"    // TYPES\n"                                                        // 16
"    typedef long long MyInt;\n"                                        // 17
"\n"                                                                    // 18
"    // DATA\n"                                                         // 19
"    int d_timesToBark;        // how many times to bark\n"             // 20
"\n"                                                                    // 21
"    // CLASS METHODS\n"                                                // 22
"    void woofWoof(int a, int b, int c);\n"                             // 23
"        // bark twice\n"                                               // 24
"\n"                                                                    // 25
"    // CREATORS\n"                                                     // 26
"    Woof(int timesToBark);\n"                                          // 27
"        // Create a Woof object initiailzed to barking\n"              // 28
"        // 'timesToBark' times.\n"                                     // 29
"\n"                                                                    // 30
"    // MANIPULATORS\n"                                                 // 31
"    void arf() {\n"                                                    // 32
"        if (woofWoof(3, 4, 12345678) * 12345678 +\n"                   // 33
"           (((47 * 34 >> 1) + 87654321)\n"                             // 34
"                 << 3) + woofWoof(\"asrf\"o, 12345678, 4)) {\n"        // 35
"            a = 4;\n"                                                  // 36
"        }\n"                                                           // 37
"    }\n"                                                               // 38
"\n"                                                                    // 39
"    // ACCESSORS\n"                                                    // 40
"    int timesToBark();\n"                                              // 41
"\n"                                                                    // 42
"};\n"                                                                  // 43
"\n"                                                                    // 44
"//=================================================================\n" // 45
"//                         INLINE FUNCTIONS\n"                         // 46
"//=================================================================\n" // 47
"\n"                                                                    // 48
"// FREE OPERATORS\n"                                                   // 49
"bool operator==(const Woof& lhs, const Woof& rhs)\n"                   // 50
"{\n"                                                                   // 51
"    return lhs.timesToBark() == rhs.timesToBark();\n"                  // 52
"}\n"                                                                   // 53
"\n"                                                                    // 54
"bool operator!=(const Woof& lhs, const Woof& rhs)\n"                   // 55
"{\n"                                                                   // 56
"    return !(lhs == rhs);\n"                                           // 57
"}\n"                                                                   // 58
"\n"                                                                    // 59
"// CREATORS\n"                                                         // 60
"inline\n"                                                              // 61
"Woof::Woof(int timesToBark)\n"                                         // 62
": d_timesToBark(timesToBark)\n"                                        // 63
"{}\n"                                                                  // 64
"\n"                                                                    // 65
"inline\n"                                                              // 66
"int Woof::run(int i)\n"                                                // 67
"{\n"                                                                   // 68
"    for (int j = 0; j < i; ++j) {\n"                                   // 69
"       for (int k = 0; k < 4; ++k) {\n"                                // 70
"           rotateClockwise90();\n"                                     // 71
"       }\n"                                                            // 72
"    }\n"                                                               // 73
"}\n"                                                                   // 74
"\n"                                                                    // 75
"}  // close namespace woof\n"                                          // 76
"\n"                                                                    // 77
"// ---------------------------------------------------------------\n"  // 78
"// NOTICE:\n"                                                          // 79
"//      Copyright (C) Bloomberg L.P., 2010\n"                          // 80
"//      All Rights Reserved.\n"                                        // 81
"//      Property of Bloomberg L.P.  (BLP)\n"                           // 82
"//      This software is made available solely pursuant to the\n"      // 83
"//      terms of a BLP license agreement which governs its use.\n"     // 84
"// ----------------------------- END-OF-FILE ---------------------\n"; // 85

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

    switch (test) { case 0:  // Zero is always the leading case.
      case -1: {
        // --------------------------------------------------------------------
        // TEST PRINTALL
        // --------------------------------------------------------------------

        Lines lines(dummyFileString1);
        Place::setEnds();

        Group::initGroups();
        Group::printAll();
        Group::clearGroups();
      }  break;
      case -2: {
        // --------------------------------------------------------------------
        // TEST WARNINGS ON A FILE GIVEN BY argv[2]
        // --------------------------------------------------------------------

        for (int f = 2; f < argc; ++f) {
            bsl::cerr << argv[f] << ':' << bsl::endl;

            Lines lines(argv[f]);
            lines.printWarnings(&cerr);
            Place::setEnds();

            if (!Lines::hasTabs()) {
                Group::initGroups();
                Group::clearGroups();
            }
        }
      }  break;
      case -3: {
        // --------------------------------------------------------------------
        // TEST WARNINGS ON A FILE GIVEN BY argv[2]
        // --------------------------------------------------------------------

        for (int f = 2; f < argc; ++f) {
            if (argc > 3) {
                bsl::cerr << argv[f] << ':' << bsl::endl;
            }

            Lines lines(argv[f]);
            Place::setEnds();
            lines.printWarnings(&cerr);

            if (Lines::hasTabs()) {
                bsl::cerr << "Ignoring " << argv[f] << " because of tabs\n";
            }
            else {
                Group::doEverything();
            }
        }
      }  break;
      case -4: {
        // --------------------------------------------------------------------
        // TEST WARNINGS ON A FILE GIVEN BY argv[2]
        // --------------------------------------------------------------------

        if (argc < 3) {
            cerr << "Usage: " << argv[0] << " -4 <files ...> <cmd>\n";
        }

        bsl::string cmd = argv[argc - 1];
        if      ("help" == cmd) {
            cout << "Commands: help, bool, doc, returns, notImp, namespaces,\n"
                           "  asserts, templates, comments, argNames, indents,"
                                                 " ifWhileFor, group, line.\n";
            break;
        }
        else if ("bool" == cmd) {
            cout << "Check boolean names\n";
        }
        else if ("doc" == cmd) {
            cout << "Check function doc\n";
        }
        else if ("returns" == cmd) {
            cout << "Check returns\n";
        }
        else if ("notImp" == cmd) {
            cout << "Check not implemented\n";
        }
        else if ("namespaces" == cmd) {
            cout << "Check namespace endings\n";
        }
        else if ("asserts" == cmd) {
            cout << "Check starting asserts\n";
        }
        else if ("templates" == cmd) {
            cout << "Check templates\n";
        }
        else if ("comments" == cmd) {
            cout << "Check comments\n";
        }
        else if ("argNames" == cmd) {
            cout << "Check arg names\n";
        }
        else if ("indents" == cmd) {
            cout << "Check for indentation errors\n";
        }
        else if ("ifWhileFor" == cmd) {
            cout << "Check only blocks controlled by if/while/for\n";
        }
        else if ("callArgs" == cmd) {
            cout << "Check routing args are indented right\n";
        }
        else if ("line" == cmd) {
            cout << "Check line-level errors\n";
        }
        else if ("group" == cmd) {
            cout << "Check group parsing sanity\n";
        }
        else {
            cerr << "Unrecognized command '" << cmd << "'\n";
            cerr << "Usage: " << argv[0] << " -4 <files ...> <cmd>\n";
            break;
        }

        for (int f = 2; f < argc - 1; ++f) {
            if (argc > 4) {
                bsl::cout << argv[f] << ':' << bsl::endl;
            }

            Lines lines(argv[f]);
            Place::setEnds();

            if ("line" == cmd) {
                lines.printWarnings(&cerr);
                continue;
            }
            if (Lines::hasTabs()) {
                cerr << "Error: " << argv[f] << " has tab(s) -- ignored\n";
                continue;
            }

            Group::initGroups();

            if ("bool" == cmd) {
                Group::checkAllBooleanRoutineNames();
            }
            else if ("doc" == cmd) {
                Group::checkAllFunctionDoc();
            }
            else if ("returns" == cmd) {
                Group::checkAllReturns();
            }
            else if ("notImp" == cmd) {
                Group::checkAllNotImplemented();
            }
            else if ("namespaces" == cmd) {
                Group::checkAllNamespaces();
            }
            else if ("asserts" == cmd) {
                Group::checkAllStartingAsserts();
            }
            else if ("templates" == cmd) {
                Group::checkAllTemplateOnOwnLine();
            }
            else if ("comments" == cmd) {
                Group::checkAllCodeComments();
            }
            else if ("argNames" == cmd) {
                Group::checkAllArgNames();
            }
            else if ("indents" == cmd) {
                Group::checkAllCodeIndents();
            }
            else if ("ifWhileFor" == cmd) {
                Group::checkAllIfWhileFor();
            }
            else if ("callArgs" == cmd) {
                Group::checkAllRoutineCallArgLists();
            }
            else if ("group" == cmd) {
                ;    // do nothing
            }
            else {
                cerr << "Internal error: cmd = '" << cmd << "'\n";
            }

            Group::clearGroups();
        }
      }  break;
      case -5: {
        // --------------------------------------------------------------------
        // PRINT GROUPS FOR FILE
        // --------------------------------------------------------------------

        for (int f = 2; f < argc; ++f) {
            bsl::cerr << argv[f] << ':' << bsl::endl;

            Lines lines(argv[f]);
            Place::setEnds();

            Group::initGroups();
            Group::printAll();
            Group::clearGroups();
        }
      }  break;
      case -6: {
        // --------------------------------------------------------------------
        // DUMP LINES FOR FILE
        // --------------------------------------------------------------------

        for (int f = 2; f < argc; ++f) {
            bsl::cerr << argv[f] << ':' << bsl::endl;

            Lines lines(argv[f]);
            Place::setEnds();

            for (int li = 1; li < Lines::lineCount(); ++li) {
                printf("%4d: %s", li, Lines::line(li).c_str());
                Lines::CommentType c = Lines::comment(li);
                if (Lines::BDEFLAG_NONE != c) {
                    printf("// %s", Lines::commentAsString(c).c_str());
                }
                printf("\n");
            }
        }
      }  break;
      case -7: {
        // --------------------------------------------------------------------
        // SHOW ERRORS IN DUMMY FILE STRING
        // --------------------------------------------------------------------

        Lines lines(dummyFileString1);
        Place::setEnds();

        Group::doEverything();
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
