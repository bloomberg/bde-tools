// csamisc_strictaliasing.cpp                                         -*-C++-*-

#include <clang/AST/ExprCXX.h>
#include <csabase_analyser.h>
#include <csabase_registercheck.h>
#include <csabase_report.h>
#include <string>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("strict-alias");

// ----------------------------------------------------------------------------

CanQualType getType(QualType type)
{
    return (type->isPointerType() ? type->getPointeeType() : type)
        ->getCanonicalTypeUnqualified();
}

static void check(Analyser& analyser, CastExpr const *expr)
{
    if (expr->getSubExpr()->isNullPointerConstant(
            *analyser.context(), Expr::NPC_ValueDependentIsNotNull)) {
        return;                                                       // RETURN
    }
    if (expr->getCastKind() != CK_BitCast &&
        expr->getCastKind() != CK_LValueBitCast &&
        expr->getCastKind() != CK_IntegralToPointer) {
        return;                                                       // RETURN
    }
    CanQualType source(getType(expr->getSubExpr()->getType()));
    CanQualType target(getType(expr->getType()));
    std::string tt = static_cast<QualType>(target).getAsString();
    if ((source != target &&
         tt != "char" &&
         tt != "unsigned char" &&
         tt != "signed char" &&
         tt != "void") ||
        (expr->getType()->isPointerType() !=
         expr->getSubExpr()->getType()->isPointerType())) {
        analyser.report(expr, check_name, "AL01",
                        "Possible strict-aliasing violation")
            << expr->getSourceRange();
    }
}

// ----------------------------------------------------------------------------

static void checkCCast(Analyser& analyser, CStyleCastExpr const *expr)
{
    check(analyser, expr);
}

static void
checkReinterpretCast(Analyser& analyser,
                     CXXReinterpretCastExpr const *expr)
{
    check(analyser, expr);
}

static RegisterCheck register_check0(check_name, checkCCast);
static RegisterCheck register_check1(check_name, checkReinterpretCast);

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
