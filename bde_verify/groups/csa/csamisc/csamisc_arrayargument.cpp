// csamisc_arrayargument.cpp                                          -*-C++-*-

#include <clang/AST/DeclTemplate.h>
#include <csabase_analyser.h>
#include <csabase_report.h>
#include <csabase_registercheck.h>
#include <csabase_visitor.h>

using namespace clang;
using namespace csabase;

static std::string const check_name("array-argument");

// ----------------------------------------------------------------------------

namespace
{

struct data
{
};

struct report : Report<data>
{
    using Report<data>::Report;

    void operator()(const FunctionDecl *decl);

    void operator()(const FunctionTemplateDecl *decl);
};


void report::operator()(FunctionDecl const *decl)
{
    for (auto p : decl->params()) {
        if (p->getOriginalType()->isConstantArrayType()) {
            a.report(p, check_name, "AA01",
                     "Pointer parameter disguised as sized array");
        }
    }
}

void report::operator()(FunctionTemplateDecl const *decl)
{
    (*this)(decl->getTemplatedDecl());
}

void subscribe(Analyser& analyser, Visitor& visitor, PPObserver& observer)
// Hook up the callback functions.
{
    visitor.onFunctionDecl         += report(analyser);
    visitor.onFunctionTemplateDecl += report(analyser);
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
