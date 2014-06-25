// csamisc_charvsstring.cpp                                           -*-C++-*-

#include <clang/AST/ASTContext.h>
#include <clang/AST/CanonicalType.h>
#include <clang/AST/Decl.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/Expr.h>
#include <clang/AST/ExprCXX.h>
#include <clang/AST/OperationKinds.h>
#include <clang/AST/Type.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/Support/Casting.h>
#include <string>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("char-vs-string");

// -----------------------------------------------------------------------------

static void check(Analyser& analyser,
                  const Expr* expr,
                  Expr** args,
                  unsigned numArgs,
                  const FunctionDecl* decl)
{
    QualType charConst(analyser.context()->CharTy.withConst());
    for (unsigned index(0); index != numArgs; ++index) {
        QualType canonArg(args[index]->getType().getCanonicalType());
        bool isCharPointer(
            canonArg.getTypePtr()->isPointerType() &&
            canonArg.getTypePtr()->getPointeeType().getCanonicalType() ==
                charConst);
        Expr const* arg(isCharPointer? args[index]: 0);
        arg = arg? arg->IgnoreParenCasts(): 0;
        UnaryOperator const* unary(arg? llvm::dyn_cast<UnaryOperator>(arg): 0);
        if (unary && unary->getOpcode() == UO_AddrOf) {
            Expr const* sub(unary->getSubExpr()->IgnoreParenCasts());
            DeclRefExpr const* ref(llvm::dyn_cast<DeclRefExpr>(sub));
            if (ref && ref->getType().getCanonicalType() ==
                           analyser.context()->CharTy) {
                analyser.report(args[index], check_name, "ADC01",
                                "Passing address of char '%0' where a "
                                "null-terminated string may be expected")
                    << ref->getDecl()->getName();
            }
        }
    }
}

// -----------------------------------------------------------------------------

static void checkCall(Analyser& analyser, CallExpr const* expr)
{
    if (FunctionDecl const* decl = expr->getDirectCallee()) {
        check(analyser,
              expr,
              const_cast<CallExpr*>(expr)->getArgs(),
              expr->getNumArgs(),
              decl);
    }
}

static void checkCtor(Analyser& analyser, CXXConstructExpr const* expr)
{
    check(analyser,
          expr,
          expr->getArgs(),
          expr->getNumArgs(),
          expr->getConstructor());
}

// -----------------------------------------------------------------------------

static RegisterCheck register_check0(check_name, &checkCall);
static RegisterCheck register_check1(check_name, &checkCtor);

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
