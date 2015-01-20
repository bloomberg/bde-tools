// csamisc_namespacetags.cpp                                          -*-C++-*-

#include <clang/AST/Decl.h>
#include <csabase_analyser.h>
#include <csabase_config.h>
#include <csabase_registercheck.h>
#include <string>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("namespace-tags");

static void namespace_tags(Analyser& analyser, NamespaceDecl const *decl)
{
    SourceLocation rbr = decl->getRBraceLoc();
    if (   analyser.is_component(decl)
        && rbr.isValid()
        && analyser.manager().getPresumedLineNumber(decl->getLocation()) !=
           analyser.manager().getPresumedLineNumber(rbr)) {
        SourceRange line_range = analyser.get_line_range(rbr);
        line_range.setBegin(rbr);
        llvm::StringRef line = analyser.get_source(line_range, true);
        std::string nsname = decl->getNameAsString();
        std::string tag;
        if (decl->isAnonymousNamespace()) {
            tag = "unnamed";
        } else if (nsname == analyser.package()) {
            tag = "package";
        } else if (nsname == analyser.config()->toplevel_namespace()) {
            tag = "enterprise";
        }
        std::string s = tag.size() ? "}  // close " + tag + " namespace" :
                                     "}  // close namespace " + nsname;
        if (line != s) {
            analyser.report(rbr, check_name, "NT01",
                            "End of %0 namespace should be marked with \"%1\"")
                << (nsname.size() ? nsname : "anonymous") << s;
            analyser.ReplaceText(line_range, s);
        }
    }
}

// -----------------------------------------------------------------------------

static RegisterCheck check(check_name, &namespace_tags);

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
