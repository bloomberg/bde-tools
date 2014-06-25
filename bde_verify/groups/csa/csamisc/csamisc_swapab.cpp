// csamisc_swapab.cpp                                                 -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/DeclTemplate.h>
#include <clang/AST/DeclarationName.h>
#include <clang/AST/Type.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <llvm/ADT/StringRef.h>
#include <string>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("swap-a-b");

// ----------------------------------------------------------------------------

namespace
{

void allFunDecls(Analyser& analyser, const FunctionDecl* func)
    // Callback function for inspecting function declarations.
{
    const ParmVarDecl *pa;
    const ParmVarDecl *pb;

    if (   func->getDeclName().isIdentifier()
        && func->getName() == "swap"
        && func->getNumParams() == 2
        && (pa = func->getParamDecl(0))->getType() ==
           (pb = func->getParamDecl(1))->getType()
        && (   pa->getType()->isPointerType()
            || pa->getType()->isReferenceType()
            )
        ) {
        if (!pa->getName().empty() && pa->getName() != "a") {
            analyser.report(pa->getLocStart(), check_name, "SWAB01",
                            "First parameter of 'swap' should be named 'a'")
                << pa->getSourceRange();
        }
        if (!pb->getName().empty() && pb->getName() != "b") {
            analyser.report(pb->getLocStart(), check_name, "SWAB01",
                            "Second parameter of 'swap' should be named 'b'")
                << pb->getSourceRange();
        }
    }
}
 
void allTpltFunDecls(Analyser& analyser, const FunctionTemplateDecl* func)
    // Callback function for inspecting function template declarations.
{
    allFunDecls(analyser, func->getTemplatedDecl());
}

}  // close anonymous namespace

// ----------------------------------------------------------------------------

static RegisterCheck c1(check_name, &allFunDecls);
static RegisterCheck c2(check_name, &allTpltFunDecls);

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
