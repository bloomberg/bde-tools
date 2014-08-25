// csamisc_cstylecastused.cpp                                         -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/DeclTemplate.h>
#include <clang/AST/Expr.h>
#include <clang/AST/OperationKinds.h>
#include <clang/AST/Stmt.h>
#include <clang/AST/StmtIterator.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <llvm/Support/Casting.h>
#include <string>

using namespace clang;
using namespace csabase;

// ----------------------------------------------------------------------------

static std::string const check_name("c-cast");

// ----------------------------------------------------------------------------

static void
check_cast(Analyser& analyser, CStyleCastExpr const* expr)
{
    switch (expr->getCastKind()) {
      case CK_NullToPointer:
      case CK_NullToMemberPointer:
      case CK_MemberPointerToBoolean:
      case CK_PointerToBoolean:
      case CK_ToVoid:
      case CK_IntegralCast:
      case CK_IntegralToBoolean:
      case CK_IntegralToFloating:
      case CK_FloatingToIntegral:
      case CK_FloatingToBoolean:
      case CK_FloatingCast:
        break;
      default: {
          if (!expr->getLocStart().isMacroID() &&
              !expr->getSubExprAsWritten()->isNullPointerConstant(
                   *analyser.context(), Expr::NPC_ValueDependentIsNotNull)) {
            analyser.report(expr, check_name, "CC01", "C-style cast is used")
                << expr->getSourceRange();
        }
      } break;
    }
}

static void find_casts(Analyser& analyser, const Stmt *stmt)
{
    Stmt::const_child_iterator b = stmt->child_begin();
    Stmt::const_child_iterator e = stmt->child_end();
    for (Stmt::const_child_iterator i = b; i != e; ++i) {
        if (*i) {
            find_casts(analyser, *i);
            const CStyleCastExpr *expr = llvm::dyn_cast<CStyleCastExpr>(*i);
            if (expr) {
                check_cast(analyser, expr);
            }
        }
    }
}

static void check_f(Analyser& analyser, FunctionDecl const* decl)
{
    if (decl->hasBody() &&
        decl->getBody() &&
        !decl->isTemplateInstantiation()) {
        find_casts(analyser, decl->getBody());
    }
}

static void check_ft(Analyser& analyser, FunctionTemplateDecl const* decl)
{
    check_f(analyser, decl->getTemplatedDecl());
}

// ----------------------------------------------------------------------------

static RegisterCheck c1(check_name, &check_f);
static RegisterCheck c2(check_name, &check_ft);

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
