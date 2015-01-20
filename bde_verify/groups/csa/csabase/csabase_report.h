// csabase_report.h                                                   -*-C++-*-

#ifndef INCLUDED_CSABASE_REPORT
#define INCLUDED_CSABASE_REPORT

#include <clang/Basic/SourceManager.h>

#include <csabase_analyser.h>
#include <csabase_ppobserver.h>

namespace csabase
{

template <class Data>
struct Report
{
    Report(Analyser& analyser,
           PPObserver::CallbackType type = PPObserver::e_None);
        // Create an object of this type, that will use the specified
        // 'analyser'.  Optionally specify a 'type' to identify the callback
        // that will be invoked, for preprocessor callbacks that have the same
        // signature.

    Analyser& d_analyser;             // 'analyser' from the constructor
    Analyser& a;

    Data& d_data;                     // persistent data for this check
    Data& d;

    PPObserver::CallbackType d_type;  // 'type' from the constructor
    PPObserver::CallbackType t;

    clang::SourceManager& d_source_manager;  // extracted from 'analyser' for
    clang::SourceManager& m;                 // convenience due to frequent use
};

}  // end package namespace

template <class Data>
csabase::Report<Data>::Report(csabase::Analyser& analyser,
                              csabase::PPObserver::CallbackType type)
: d_analyser(analyser)
, a(analyser)
, d_data(analyser.attachment<Data>())
, d(analyser.attachment<Data>())
, d_type(type)
, t(type)
, d_source_manager(analyser.manager())
, m(analyser.manager())
{
}

// -----------------------------------------------------------------------------

#endif

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
