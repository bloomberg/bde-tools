// bdeflag.m.cpp                                                      -*-C++-*-

#include <bdeflag_componenttable.h>
#include <bdeflag_group.h>
#include <bdeflag_lines.h>
#include <bdeflag_place.h>
#include <bdeflag_ut.h>

#include <bsl_iostream.h>
#include <bsl_string.h>

#include <bsl_cstdio.h>

using namespace BloombergLP;
using namespace bdeflag;

// ============================================================================
//                                 MAIN PROGRAM
// ============================================================================

int main(int argc, char *argv[])
{
#if 0
    for (int f = 1; f < argc; ++f) {
        if (argc > 2) {
            bsl::cerr << argv[f] << ':' << bsl::endl;
        }

        Lines lines(argv[f]);
        lines.printWarnings(&bsl::cerr);
        if (!Lines::couldntOpenFile()) {
            Place::setEnds();
            Group::doEverything();
        }
    }
#endif

    bsl::string argv1;
    if (argc > 1) {
        argv1 = argv[1];
    }

    if (2 == argc && (argv1 == "-h" || argv1 == "--help")) {
        bsl::cerr <<
            "-h                         : this message\n"
            "--brace_report <sourceFile>: dump out report of {}() nesting\n"
            "<src1> <src2> ...          : generate bdeflag warnings for\n"
            "                             unlimited # of source files\n";
        return 0;                                                     // RETURN
    }
    else if (3 == argc && argv1 == "--brace_report") {
        Lines lines(argv[2]);
        if (Lines::couldntOpenFile()) {
            bsl::cerr << "Error: couldn't open file '" << argv[2] << "\n";
            return 1;                                                 // RETURN
        }
        else {
            Lines::braceReport();
            return 0;                                                 // RETURN
        }
    }

    ComponentTable table;

    for (int f = 1; f < argc; ++f) {
        bsl::string fn(argv[f]);

        if (!table.addFileOrComponentName(fn)) {
            bsl::cerr << "Error: file or component '" << fn <<
                                                          "' doesn't exist.\n";
        }
    }

    int numFiles = 0;
    const bsl::size_t NUM_COMPONENTS = table.length();
    for (bsl::size_t i = 0; i < NUM_COMPONENTS; ++i) {
        numFiles += table.component(i).numFiles();
    }

    for (bsl::size_t i = 0; i < NUM_COMPONENTS; ++i) {
        const ComponentTable::Component& component = table.component(i);

        const ComponentTable::FileNameSetIterator end = component.end();
        for (ComponentTable::FileNameSetIterator it = component.begin();
                                                             end != it; ++it) {
            const bsl::string& fn = *it;
            if (numFiles > 1) {
                bsl::cerr << fn << ':' << bsl::endl;
            }

            Lines lines(fn.c_str());
            lines.printWarnings(&bsl::cerr);
            if (!Lines::couldntOpenFile()) {
                Place::setEnds();
                Group::doEverything();
            }
        }
    }

    return 0;
}

// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P.  (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------
