// csamisc_longinline.cpp                                             -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/Expr.h>
#include <clang/AST/Stmt.h>
#include <clang/AST/StmtIterator.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Basic/SourceManager.h>
#include <csabase_analyser.h>
#include <csabase_config.h>
#include <csabase_registercheck.h>
#include <llvm/Support/Casting.h>
#include <string.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace csabase { class PPObserver; }
namespace csabase { class Visitor; }

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("long-inline");

// ----------------------------------------------------------------------------

namespace
{

// Data attached to analyzer for this check.
struct data
{
    enum E {
        e_ENDS_IN_OTHER_FILE,
        e_TOO_LONG,
        e_CONFUSED,
    };

    unsigned d_max_lines;

    // Function and its problem.
    typedef std::vector<std::pair<const FunctionDecl*, E> > VecFE;
    VecFE d_long_inlines;
};

// Count statements in a statement.
unsigned count_statements(const Stmt *stmt)
{
    unsigned count = 0;
    if (stmt) {
        // Don't penalize compound or labeled statements.
        // Don't double count statements and controlling expressions.
        if (   !llvm::dyn_cast<CompoundStmt>(stmt)
            && !llvm::dyn_cast<LabelStmt>(stmt)
            && !llvm::dyn_cast<IfStmt>(stmt)
            && !llvm::dyn_cast<DoStmt>(stmt)
            && !llvm::dyn_cast<ForStmt>(stmt)
            && !llvm::dyn_cast<WhileStmt>(stmt)
            && !llvm::dyn_cast<SwitchStmt>(stmt)) {
            ++count;
        }
        // Don't count subexpressions.
        if (   !llvm::dyn_cast<Expr>(stmt)
            && !llvm::dyn_cast<ReturnStmt>(stmt)
            && !llvm::dyn_cast<DeclStmt>(stmt)) {
            for (ConstStmtRange kids = stmt->children(); kids; ++kids) {
                count += count_statements(*kids);
            }
        }
    }
    return count;
}

// Callback function for inspecting function declarations.
void long_inlines(Analyser& analyser, const FunctionDecl* func)
{
    // Process only function definitions, not declarations.
    if (func->hasBody() && func->getBody() && func->isInlineSpecified()) {
        data&           d    = analyser.attachment<data>();
        data::VecFE&    ad   = d.d_long_inlines;
        Stmt           *body = func->getBody();
        SourceManager&  sm   = analyser.manager();
        PresumedLoc     b    = sm.getPresumedLoc(body->getLocStart());
        PresumedLoc     e    = sm.getPresumedLoc(body->getLocEnd());

        if (b.isInvalid() || e.isInvalid()) {
            ad.push_back(std::make_pair(func, data::e_CONFUSED));
        } else if (strcmp(b.getFilename(), e.getFilename()) != 0) {
            ad.push_back(std::make_pair(func, data::e_ENDS_IN_OTHER_FILE));
        } else if (e.getLine() < b.getLine()) {
            ad.push_back(std::make_pair(func, data::e_CONFUSED));
        } else if (e.getLine() - b.getLine() > d.d_max_lines &&
                   count_statements(body)    > d.d_max_lines) {
            ad.push_back(std::make_pair(func, data::e_TOO_LONG));
        }
    }
}

// Callback object invoked upon completion.
struct report
{
    Analyser* d_analyser;

    report(Analyser& analyser) : d_analyser(&analyser) {}

    void operator()()
    {
        const data& d = d_analyser->attachment<data>();
        process(d.d_long_inlines.begin(), d.d_long_inlines.end());
    }

    template <class IT>
    void process(IT begin, IT end)
    {
        const data& d = d_analyser->attachment<data>();
        for (IT it = begin; it != end; ++it) {
            std::ostringstream ss;
            switch (it->second) {
              case data::e_ENDS_IN_OTHER_FILE: {
                  ss << "Inline function spans source files";
              } break;
              case data::e_TOO_LONG: {
                  ss << "Inline function is more than "
                     << d.d_max_lines
                     << " lines long";
              } break;
              case data::e_CONFUSED: {
                  ss << "Compiler state for inline function is confused";
              } break;
              default: {
                  ss << "Unknown inline function problem " << it->second;
              } break;
            }
            d_analyser->report(it->first, check_name, "LI01", ss.str())
                << it->first->getNameInfo().getSourceRange();
        }
    }
};

void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
{
    std::istringstream is(analyser.config()->value("max_inline_lines"));
    data&              d = analyser.attachment<data>();
    if (!(is >> d.d_max_lines)) {
        d.d_max_lines = 10;
    }

    analyser.onTranslationUnitDone += report(analyser);
}

}  // close anonymous namespace

// ----------------------------------------------------------------------------

static RegisterCheck c1(check_name, &long_inlines);
static RegisterCheck c2(check_name, &subscribe);

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
