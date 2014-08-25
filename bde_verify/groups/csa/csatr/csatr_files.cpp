// csatr_files.cpp                                                    -*-C++-*-

#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_filenames.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <llvm/ADT/StringRef.h>
#include <sys/stat.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <string>

namespace csabase { class Visitor; }

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("files");

// -----------------------------------------------------------------------------

namespace
{
    struct on_files_open
    {
        on_files_open(Analyser& analyser) : d_analyser(analyser)
        {
        }

        void operator()(SourceLocation where,
                        std::string const&,
                        std::string const& name) const
        {
            FileName fn(name);
            if (fn.name().find("m_") != 0 && name == d_analyser.toplevel()) {
                struct stat buffer;
                std::string prefix =
                    fn.directory().str() + fn.component().str();
                std::string pkg_prefix =
                    fn.pkgdir().str() + fn.component().str();
                if (stat((    prefix + ".h").c_str(), &buffer) &&
                    stat((pkg_prefix + ".h").c_str(), &buffer)) {
                    d_analyser.report(where, check_name, "FI01",
                            "Header file '%0' not accessible", true)
                        << (pkg_prefix + ".h");
                }
                if (stat((    prefix + ".t.cpp").c_str(), &buffer) &&
                    stat((pkg_prefix + ".t.cpp").c_str(), &buffer)) {
                    d_analyser.report(where, check_name, "FI02",
                            "Test file '%0' not accessible", true)
                        << (pkg_prefix + ".t.cpp");
                }
            }
        }

        Analyser& d_analyser;
    };
}

static void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
{
    observer.onOpenFile  += on_files_open(analyser);
}

// -----------------------------------------------------------------------------

static RegisterCheck register_observer(check_name, &subscribe);

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
