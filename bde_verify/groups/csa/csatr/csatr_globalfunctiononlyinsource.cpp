// csatr_globalfunctiononlyinsource.cpp                               -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/DeclarationName.h>
#include <clang/AST/Redeclarable.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_location.h>
#include <csabase_registercheck.h>
#include <llvm/Support/Casting.h>
#include <algorithm>
#include <string>

namespace clang { class Decl; }

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("global-function-only-in-source");

// ----------------------------------------------------------------------------

namespace
{
    struct decl_not_in_toplevel
    {
        decl_not_in_toplevel(Analyser* analyser) : analyser_(analyser)
        {
        }

        bool operator()(Decl const* decl) const
        {
            return analyser_->get_location(decl).file()
                != analyser_->toplevel();
        }

        Analyser* analyser_;
    };
}

// ----------------------------------------------------------------------------

static void
global_function_only_in_source(Analyser& analyser, FunctionDecl const* decl)
{
    if (decl->isGlobal()
        && llvm::dyn_cast<CXXMethodDecl>(decl) == 0
        && !analyser.is_component_header(analyser.toplevel())
        && analyser.get_location(decl).file() == analyser.toplevel()
        && std::find_if(decl->redecls_begin(), decl->redecls_end(),
                        decl_not_in_toplevel(&analyser))
            == decl->redecls_end()
        && !analyser.is_test_driver()
        && !decl->isMain())
    {
        analyser.report(decl, check_name, "TR10",
                        "Globally visible function '%0' "
                        "is not declared in header.")
                        << decl->getQualifiedNameAsString()
                        << decl->getNameInfo().getSourceRange();
    }
}

// ----------------------------------------------------------------------------

static RegisterCheck check(check_name, &global_function_only_in_source);

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
