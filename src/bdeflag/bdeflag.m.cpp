// bdeflag.m.cpp                                                      -*-C++-*-

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
