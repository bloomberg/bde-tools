// csafmt_headline.cpp                                                -*-C++-*-

#include <clang/Basic/Diagnostic.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Basic/SourceManager.h>
#include <clang/Rewrite/Core/Rewriter.h>
#include <csabase_analyser.h>
#include <csabase_binder.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_filenames.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <csabase_util.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/Support/MemoryBuffer.h>
#include <stddef.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <string>
#include <utility>

namespace csabase { class Visitor; }

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("headline");

// ----------------------------------------------------------------------------

static void open_file(Analyser& analyser,
                      SourceLocation where,
                      const std::string&,
                      const std::string& name)
{
    FileName fn(name);
    std::string filename = fn.name();
    if (analyser.is_component_header(filename) ||
        name == analyser.toplevel()) {
        const SourceManager &m = analyser.manager();
        llvm::StringRef buf = m.getBuffer(m.getFileID(where))->getBuffer();
        buf = buf.substr(0, buf.find('\n')).rtrim();
        std::string expectcpp("// " + filename);
        expectcpp.resize(70, ' ');
        expectcpp += "-*-C++-*-";
        std::string expectc("/* " + filename);
        expectc.resize(69, ' ');
        expectc += "-*-C-*- */";

        if (   !buf.equals(expectcpp)
            && !buf.equals(expectc)
            && buf.find("GENERATED") == buf.npos) {
            std::pair<size_t, size_t> mcpp = mid_mismatch(buf, expectcpp);
            std::pair<size_t, size_t> mc = mid_mismatch(buf, expectc);
            std::pair<size_t, size_t> m;
            std::string expect;

            if (mcpp.first >= mc.first || mcpp.second >= mc.second) {
                m = mcpp;
                expect = expectcpp;
            } else {
                m = mc;
                expect = expectc;
            }
            analyser.report(where.getLocWithOffset(m.first),
                            check_name, "HL01",
                            "File headline incorrect", true);
            analyser.report(where.getLocWithOffset(m.first),
                            check_name, "HL01",
                            "Correct format is\n%0",
                            true, DiagnosticsEngine::Note)
                << expect;
            if (m.first == 0) {
                analyser.rewriter().InsertText(
                    where.getLocWithOffset(m.first),
                    expect + "\n");
            } else {
                analyser.rewriter().ReplaceText(
                    analyser.get_line_range(where), expect);
            }
        }
    }
}

// ----------------------------------------------------------------------------

static void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
{
    observer.onOpenFile += bind<Analyser&>(analyser, open_file);
}

// ----------------------------------------------------------------------------

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
