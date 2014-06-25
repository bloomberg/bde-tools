// csamisc_verifysameargumentnames.cpp                                -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/Redeclarable.h>
#include <clang/Basic/Diagnostic.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <llvm/Support/Casting.h>
#include <algorithm>
#include <string>

namespace clang { class Decl; }

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("verify-same-argument-names");

// -----------------------------------------------------------------------------

namespace
{
bool arg_names_match(ParmVarDecl const* p0, ParmVarDecl const* p1)
{
    std::string n0(p0->getNameAsString());
    std::string n1(p1->getNameAsString());
    bool rc = n0.empty() || n1.empty() || n0 == n1;
    return rc;
}

struct same_argument_names
{
    same_argument_names(Analyser* analyser, FunctionDecl const* current)
    : analyser_(analyser), current_(current)
    {
    }

    void operator()(Decl const* decl)
    {
        if (FunctionDecl const* p = llvm::dyn_cast<FunctionDecl>(decl)) {
            FunctionDecl const* c(current_);
            unsigned n = p->getNumParams();
            if (n == c->getNumParams()) {
                for (unsigned i = 0; i < n; ++i) {
                    const ParmVarDecl* pp = p->getParamDecl(i);
                    const ParmVarDecl* cp = c->getParamDecl(i);
                    if (!arg_names_match(pp, cp)) {
                        analyser_->report(cp->getLocation(),
                                          check_name, "AN01",
                                          "Parameter name mismatch for "
                                          "%ordinal0 parameter %1")
                            << int(i + 1) << cp;
                        analyser_->report(pp->getLocation(),
                                          check_name, "AN01",
                                          "The other declaration uses %0",
                                          false,
                                          DiagnosticsEngine::Note)
                            << pp;
                    }
                }
            }
        }
    }

    Analyser* analyser_;
    FunctionDecl const* current_;
};
}

// -----------------------------------------------------------------------------

static void
verify_arg_names_match(Analyser& analyser, FunctionDecl const* decl)
{
    if (!decl->isFirstDecl()) {
        std::for_each(decl->redecls_begin(),
                      decl->redecls_end(),
                      same_argument_names(&analyser, decl));
    }
}

// -----------------------------------------------------------------------------

static RegisterCheck check(check_name, &verify_arg_names_match);

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
