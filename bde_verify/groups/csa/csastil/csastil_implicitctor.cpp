// csastil_implicitctor.cpp                                           -*-C++-*-

#include <clang/AST/DeclBase.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/DeclTemplate.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_location.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/Support/Casting.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <set>
#include <string>
#include <vector>

namespace csabase { class Visitor; }

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("implicit-ctor");

// -----------------------------------------------------------------------------

namespace
{
    struct suppressions
    {
        std::set<Location>       entries_;
        std::vector<Decl const*> reports_;
    };
}

// -----------------------------------------------------------------------------

static void check(Analyser& analyser, CXXConstructorDecl const* decl)
{
    if (decl->isConvertingConstructor(false)
        && !decl->isCopyOrMoveConstructor()
        && decl->isFirstDecl()
        && !llvm::dyn_cast<ClassTemplateSpecializationDecl>(decl->getParent())
        ) {
        analyser.attachment<suppressions>().reports_.push_back(decl);
    }
}

// -----------------------------------------------------------------------------
        
namespace
{
    struct report
    {
        report(Analyser& analyser): analyser_(&analyser) {}

        void operator()()
        {
            //-dk:TODO the suppression handling should be in a shared place!
            suppressions const& attachment(
                analyser_->attachment<suppressions>());
            for (Decl const* decl : attachment.reports_) {
                typedef std::set<Location>::const_iterator const_iterator;
                SourceLocation end(decl->getLocStart());
                Location loc(analyser_->get_location(end));
                const_iterator it(attachment.entries_.lower_bound(loc));
                Decl const* next(decl->getNextDeclInContext());

                if (it == attachment.entries_.end() ||
                    (next &&
                     analyser_->get_location(next->getLocStart()) < *it &&
                     loc < analyser_->get_location(next->getLocation())) ||
                    it->file() != loc.file() ||
                    (it->line() != loc.line() &&
                     it->line() != loc.line() + 1) ||
                    it->column() != 69) {
                    analyser_->report(decl, check_name, "IC01",
                            "Constructor suitable for implicit conversions")
                        << decl->getSourceRange();
                }
            }
        }

        Analyser* analyser_;
    };
}

// -----------------------------------------------------------------------------

namespace
{
    struct tags
    {
        tags(Analyser& analyser) : analyser_(&analyser)
        {
        }

        void operator()(SourceRange range)
        {
            Location location(analyser_->get_location(range.getBegin()));
            if (analyser_->is_component(location.file())) {
                std::string comment(analyser_->get_source(range));
                if (comment == "// IMPLICIT") {
                    analyser_->attachment<suppressions>().entries_.insert(
                        location);
                }
            }
        }

        Analyser* analyser_;
    };
}

static void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
{
    analyser.onTranslationUnitDone += report(analyser);
    observer.onComment += tags(analyser);
}

// -----------------------------------------------------------------------------

static RegisterCheck register_check(check_name, &check);
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
