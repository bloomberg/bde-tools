// csabase_diagnosticfilter.h                                         -*-C++-*-

#ifndef INCLUDED_CSABASE_DIAGNOSTICFILTER_H
#define INCLUDED_CSABASE_DIAGNOSTICFILTER_H

#include <clang/Basic/Diagnostic.h>
#include <memory>

// ----------------------------------------------------------------------------

namespace clang { class DiagnosticOptions; }
namespace clang { class LangOptions; }
namespace clang { class Preprocessor; }

namespace csabase { class Analyser; }
namespace csabase
{
class DiagnosticFilter : public clang::DiagnosticConsumer
{
public:
    DiagnosticFilter(Analyser const& analyser,
                     bool toplevel_only,
                     clang::DiagnosticOptions & options);
    ~DiagnosticFilter();

    void BeginSourceFile(clang::LangOptions const&  opts,
                         clang::Preprocessor const* pp);
    void EndSourceFile();
    bool IncludeInDiagnosticCount() const;
    clang::DiagnosticConsumer* clone(clang::DiagnosticsEngine&) const;
    void HandleDiagnostic(clang::DiagnosticsEngine::Level level,
                          clang::Diagnostic const&        info);

private:
    DiagnosticFilter(DiagnosticFilter const&);
    void operator=(DiagnosticFilter const&);

    clang::DiagnosticOptions *               d_options;
    std::auto_ptr<clang::DiagnosticConsumer> d_client;
    Analyser const*                          d_analyser;
    bool                                     d_toplevel_only;
};
}

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
