// csabbg_allocatornewwithpointer.cpp                                 -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/Expr.h>
#include <clang/AST/ExprCXX.h>
#include <clang/AST/Type.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <string>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("allocator-new");

static void check(Analyser& analyser, CXXNewExpr const* expr)
{
    if (expr->getNumPlacementArgs() == 1
        && expr->getPlacementArg(0)->getType()->isPointerType())
    {
        Expr* placement(const_cast<Expr*>(expr->getPlacementArg(0))
                            ->IgnoreParenImpCasts());
        if (placement && placement->getType()->isPointerType()) {
            QualType pointee(placement->getType()->getPointeeType());
            TypeDecl* bslma_allocator(
                analyser.lookup_type("::BloombergLP::bslma_Allocator"));

            if (bslma_allocator && bslma_allocator->getTypeForDecl() &&
                bslma_allocator->getTypeForDecl()
                        ->getCanonicalTypeInternal() ==
                    pointee->getCanonicalTypeInternal()) {
                analyser.report(placement, check_name, "ANP01",
                        "Allocator new with pointer")
                    << placement->getSourceRange();
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
