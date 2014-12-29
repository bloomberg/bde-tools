// csabase_diagnosticfilter.cpp                                       -*-C++-*-

#include <csabase_diagnosticfilter.h>
#include <csabase_analyser.h>
#include <csabase_debug.h>
#include <csabase_registercheck.h>
#include <clang/Basic/FileManager.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Basic/SourceManager.h>
#include <clang/Frontend/TextDiagnosticPrinter.h>
#include <clang/Lex/LexDiagnostic.h>  // IWYU pragma: keep
// IWYU pragma: no_include <clang/Basic/DiagnosticLexKinds.inc>
#include <llvm/Support/raw_ostream.h>
#include <string>

namespace clang { class LangOptions; }
namespace clang { class Preprocessor; }
namespace clang { class TranslationUnitDecl; }

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("diagnostic-filter");

// ----------------------------------------------------------------------------

csabase::DiagnosticFilter::DiagnosticFilter(Analyser const&    analyser,
                                            std::string        diagnose,
                                            DiagnosticOptions& options)
: TextDiagnosticPrinter(llvm::errs(), &options)
, d_analyser(&analyser)
, d_diagnose(diagnose)
{
}

// ----------------------------------------------------------------------------

void
csabase::DiagnosticFilter::HandleDiagnostic(DiagnosticsEngine::Level level,
                                            Diagnostic const&        info)
{
    bool handle = false;
    if (!handle) {
        handle = !info.getLocation().isFileID() &&
                 info.getID() != diag::pp_pragma_once_in_main_file;
    }
    if (!handle) {
        handle = d_diagnose == "all";
    }
    if (!handle) {
        handle = d_diagnose == "nogen" &&
                 !d_analyser->is_generated(info.getLocation());
    }
    if (!handle) {
        handle = d_diagnose == "component" &&
                 d_analyser->is_component(info.getLocation());
    }
    if (!handle) {
        handle = d_diagnose == "main" &&
                 d_analyser->manager().getMainFileID() ==
                 d_analyser->manager().getFileID(info.getLocation());
    }
    if (handle) {
        TextDiagnosticPrinter::HandleDiagnostic(level, info);
    }
}

// ----------------------------------------------------------------------------

static void check(Analyser& analyser, const TranslationUnitDecl*)
{
}

// ----------------------------------------------------------------------------

static RegisterCheck register_check(check_name, &check);

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
