// csafmt_whitespace.cpp                                              -*-C++-*-

#include <clang/Basic/SourceLocation.h>
#include <clang/Basic/SourceManager.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <csabase_util.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/Support/Regex.h>
#include <stddef.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <string>
#include <utility>

namespace csabase { class Visitor; }

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("whitespace");

// ----------------------------------------------------------------------------

namespace
{

struct files
    // Callback object for inspecting files.
{
    Analyser& d_analyser;                   // Analyser object.

    files(Analyser& analyser);
        // Create a 'files' object, accessing the specified 'analyser'.

    void operator()(SourceLocation loc,
                    std::string const &,
                    std::string const &);
        // The file specified by 'loc' is examined for tab characters and
        // trailing spaces.
};

files::files(Analyser& analyser)
: d_analyser(analyser)
{
}

llvm::Regex bad_ws("\t+| +\n", llvm::Regex::NoFlags);

void files::operator()(SourceLocation loc,
                       std::string const &,
                       std::string const &)
{
    const SourceManager &m = d_analyser.manager();
    llvm::StringRef buf = m.getBufferData(m.getFileID(loc));
    if (d_analyser.is_component(loc) && buf.find('\t') != buf.find(" \n")) {
        loc = m.getLocForStartOfFile(m.getFileID(loc));
        size_t offset = 0;
        llvm::StringRef s;
        llvm::SmallVector<llvm::StringRef, 7> matches;
        while (bad_ws.match(s = buf.drop_front(offset), &matches)) {
            llvm::StringRef text = matches[0];
            std::pair<size_t, size_t> m = mid_match(s, text);
            size_t matchpos = offset + m.first;
            offset = matchpos + text.size();
            SourceLocation sloc = loc.getLocWithOffset(matchpos);
            if (text[0] == '\t') {
                d_analyser.report(sloc, check_name, "TAB01",
                        "Tab character%s0 in source")
                    << static_cast<long>(text.size());
                d_analyser.ReplaceText(
                    sloc, text.size(), std::string(text.size(), ' '));
            }
            else {
                d_analyser.report(loc.getLocWithOffset(matchpos),
                        check_name, "ESP01",
                        "Space%s0 at end of line")
                    << static_cast<long>(text.size() - 1);
                d_analyser.RemoveText(sloc, text.size() - 1);
            }
        }
    }
}

void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
    // Hook up the callback functions.
{
    observer.onOpenFile += files(analyser);
}

}  // close anonymous namespace

// ----------------------------------------------------------------------------

static RegisterCheck c1(check_name, &subscribe);

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
