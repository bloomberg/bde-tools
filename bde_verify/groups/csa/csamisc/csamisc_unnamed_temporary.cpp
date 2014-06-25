// csamisc_unnamed_temporary.cpp                                      -*-C++-*-

#include <clang/AST/ASTContext.h>
#include <clang/AST/Decl.h>
#include <clang/AST/DeclBase.h>
#include <clang/AST/Expr.h>
#include <clang/ASTMatchers/ASTMatchFinder.h>
#include <clang/ASTMatchers/ASTMatchers.h>
#include <clang/ASTMatchers/ASTMatchersInternal.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Basic/SourceManager.h>
#include <clang/Frontend/CompilerInstance.h>
#include <clang/Lex/Preprocessor.h>
#include <csabase_analyser.h>
#include <csabase_registercheck.h>
#include <csabase_util.h>
#include <llvm/ADT/Optional.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/ADT/VariadicFunction.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <string>

namespace clang { class ExprWithCleanups; }
namespace clang { class Stmt; }
namespace csabase { class PPObserver; }
namespace csabase { class Visitor; }

using namespace clang;
using namespace clang::ast_matchers;
using namespace clang::ast_matchers::internal;
using namespace csabase;

// ----------------------------------------------------------------------------

static std::string const check_name("unnamed-temporary");

// ----------------------------------------------------------------------------

namespace clang {
namespace ast_matchers {

const internal::VariadicDynCastAllOfMatcher<Stmt, ExprWithCleanups> cleanups;

}
}

namespace
{

struct report
    // Callback object for detecting top-level unnamed temporaries.
{
    Analyser& d_analyser;

    report(Analyser& analyser);
        // Initialize an object of this type.

    void operator()();
        // Callback for the end of the translation unit.

    void match_unnamed_temporary(const BoundNodes &nodes);
        // Callback when unnamed temporaries are found.
};

report::report(Analyser& analyser)
: d_analyser(analyser)
{
}

const internal::DynTypedMatcher &
unnamed_temporary_matcher()
    // Return an AST matcher which looks for expression statements which
    // construct temporary objects.
{
    static const internal::DynTypedMatcher matcher = decl(forEachDescendant(
        cleanups(
            hasParent(stmt(unless(expr()))),
            anyOf(
                has(functionalCastExpr()),
                has(bindTemporaryExpr(has(temporaryObjectExpr())))
            )
        ).bind("ut")
    ));
    return matcher;
}

void report::match_unnamed_temporary(const BoundNodes &nodes)
{
    const Expr* e = nodes.getNodeAs<Expr>("ut");

    // Test drivers may construct unnamed objects within various ASSERT macros
    // for negative testing purposes.
    if (d_analyser.is_test_driver()) {
        SourceManager &sm = d_analyser.manager();
        Preprocessor &pp = d_analyser.compiler().getPreprocessor();
        for (SourceLocation loc = e->getExprLoc();
             loc.isMacroID();
             loc = sm.getImmediateMacroCallerLoc(loc)) {
            StringRef macro = pp.getImmediateMacroName(loc);
            if (macro.find("ASSERT") != macro.npos) {
                return;  // RETURN
            }
        }
    }

    d_analyser.report(e, check_name, "UT01",
                      "Unnamed object will be immediately destroyed");
}

void report::operator()()
{
    MatchFinder mf;
    OnMatch<report, &report::match_unnamed_temporary> m1(this);
    mf.addDynamicMatcher(unnamed_temporary_matcher(), &m1);
    mf.match(*d_analyser.context()->getTranslationUnitDecl(),
             *d_analyser.context());
}

void subscribe(Analyser& analyser, Visitor& visitor, PPObserver& observer)
    // Hook up the callback functions.
{
    analyser.onTranslationUnitDone += report(analyser);
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
