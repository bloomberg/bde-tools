// csamisc_constantreturn.cpp                                         -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/DeclarationName.h>
#include <clang/AST/Expr.h>
#include <clang/AST/Redeclarable.h>
#include <clang/AST/Stmt.h>
#include <clang/AST/StmtIterator.h>
#include <clang/Basic/Diagnostic.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <llvm/ADT/APSInt.h>
#include <llvm/Support/Casting.h>
#include <iterator>
#include <string>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("constant-return");

// -----------------------------------------------------------------------------

static void check(Analyser& analyser, FunctionDecl const* decl)
{
    if (analyser.is_component(decl)
        && decl->hasBody()
        && decl->getBody()
        && decl->getIdentifier())
    {
        Stmt* stmt(decl->getBody());
        while (llvm::dyn_cast<CompoundStmt>(stmt) &&
               std::distance(stmt->child_begin(), stmt->child_end()) == 1) {
            stmt = *stmt->child_begin();
        }

        if (llvm::dyn_cast<ReturnStmt>(stmt)
            && llvm::dyn_cast<ReturnStmt>(stmt)->getRetValue())
        {
            ReturnStmt* ret(llvm::dyn_cast<ReturnStmt>(stmt));
            Expr* expr(ret->getRetValue());
            llvm::APSInt result;
            if (!expr->isValueDependent() &&
                expr->isIntegerConstantExpr(result, *analyser.context()))
            {
                analyser.report(expr, check_name, "CR01",
                                "Function '%0' has only one statement which "
                                "returns the constant '%1'") 
                    << decl->getNameAsString()
                    << result.toString(10)
                    << decl->getNameInfo().getSourceRange();
                for (FunctionDecl::redecl_iterator it(decl->redecls_begin()),
                     end(decl->redecls_end());
                     it != end;
                     ++it) {
                    analyser.report(*it, check_name, "CR01",
                                    "Declaration of '%0' (which always "
                                    "returns the constant %1)", false,
                                    DiagnosticsEngine::Note)
                        << decl->getNameAsString()
                        << result.toString(10)
                        << decl->getNameInfo().getSourceRange();
                }
            }
        }
    }
}

// -----------------------------------------------------------------------------

static RegisterCheck register_check(check_name, &check);

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
