// csastil_uppernames.cpp                                             -*-C++-*-

#include <clang/AST/ASTContext.h>
#include <clang/AST/Decl.h>
#include <clang/AST/DeclBase.h>
#include <clang/AST/DeclTemplate.h>
#include <clang/ASTMatchers/ASTMatchFinder.h>
#include <clang/ASTMatchers/ASTMatchers.h>
#include <clang/ASTMatchers/ASTMatchersInternal.h>
#include <clang/Basic/IdentifierTable.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_registercheck.h>
#include <csabase_util.h>
#include <llvm/ADT/Optional.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/ADT/VariadicFunction.h>
#include <llvm/Support/Casting.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <set>
#include <string>
#include <utility>

namespace csabase { class PPObserver; }
namespace csabase { class Visitor; }

using namespace clang;
using namespace clang::ast_matchers;
using namespace csabase;

// ----------------------------------------------------------------------------

static std::string const check_name("upper-case-names");

// ----------------------------------------------------------------------------

namespace
{

struct data
{
    data();

    std::set<NamedDecl const*> d_decls;
};

data::data()
{
}

struct report
    // Complain about upper-case only variables and constants.
{
    report(Analyser& analyser);
        // Create an object of this type using the specified analyser.

    void match_has_name(const BoundNodes& nodes);
        // Find named declarations.

    void operator()();
        // Callback invoked at end of translation unit.

    Analyser& d_analyser;
    data& d_data;
};

report::report(Analyser& analyser)
: d_analyser(analyser)
, d_data(analyser.attachment<data>())
{
}

const internal::DynTypedMatcher &
has_name_matcher()
    // Return an AST matcher which looks for named declarations.
{
    static const internal::DynTypedMatcher matcher =
        decl(forEachDescendant(namedDecl().bind("decl")));
    return matcher;
}

void report::match_has_name(const BoundNodes& nodes)
{
    NamedDecl const* decl = nodes.getNodeAs<NamedDecl>("decl");
    if (!d_data.d_decls.insert(decl).second) {
        return;                                                       // RETURN
    }
    if (decl->getLocation().isMacroID()) {
        return;                                                       // RETURN
    }
    if (!d_analyser.is_component(decl)) {
        return;                                                       // RETURN
    }
    if (llvm::dyn_cast<TemplateTypeParmDecl>(decl) ||
        llvm::dyn_cast<NonTypeTemplateParmDecl>(decl)) {
        return;                                                       // RETURN
    }
    if (FunctionDecl const* func = llvm::dyn_cast<FunctionDecl>(decl)) {
        if (func->isDefaulted()) {
            return;                                                   // RETURN
        }
    }
    if (RecordDecl const* record = llvm::dyn_cast<RecordDecl>(decl)) {
        if (record->isInjectedClassName()) {
            return;                                                   // RETURN
        }
    }

    IdentifierInfo const* ii = decl->getIdentifier();
    if (ii) {
        llvm::StringRef name = ii->getName();
        if (name.find_first_of("abcdefghijklmnopqrstuvwxyz") == name.npos &&
            name.find_first_of("ABCDEFGHIJKLMNOPQRSTUVWXYZ") != name.npos &&
            name.find(llvm::StringRef(d_analyser.component()).upper()) ==
                name.npos) {
            d_analyser.report(decl, check_name, "UC01",
                              "Name should not be all upper-case");
        }
    }

    if (TemplateDecl const* tplt = llvm::dyn_cast<TemplateDecl>(decl)) {
        d_data.d_decls.insert(tplt->getTemplatedDecl());
    }
}

void report::operator()()
{
    if (!d_analyser.is_test_driver()) {
        MatchFinder mf;
        OnMatch<report, &report::match_has_name> m1(this);
        mf.addDynamicMatcher(has_name_matcher(), &m1);
        mf.match(*d_analyser.context()->getTranslationUnitDecl(),
                 *d_analyser.context());
    }
}

void subscribe(Analyser& analyser, Visitor&, PPObserver&)
{
    analyser.onTranslationUnitDone += report(analyser);
}

}

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
