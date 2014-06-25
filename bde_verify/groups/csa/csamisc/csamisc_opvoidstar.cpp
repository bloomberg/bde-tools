// csamisc_opvoidstar.cpp                                             -*-C++-*-

#include <clang/AST/DeclCXX.h>
#include <clang/AST/Type.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_location.h>
#include <csabase_registercheck.h>
#include <string>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("operator-void-star");

// ----------------------------------------------------------------------------

namespace
{

void conversions(Analyser& analyser, const CXXConversionDecl* conv)
    // Callback function for inspecting conversion declarations.
{
    Location loc(analyser.get_location(conv->getLocStart()));
    if (analyser.is_component(loc.file()))
    {
        QualType type = conv->getConversionType();
        if (   !conv->isExplicit()
            && (   type->isBooleanType()
                || (   type->isPointerType()
                    && type->getPointeeType()->isVoidType()
                    )
                )
            ) {
            analyser.report(conv, check_name, "CB01",
                            "Consider using conversion to "
                            "bsls::UnspecifiedBool<%0>::BoolType instead")
                << conv->getParent()->getNameAsString();
        }
    }
}

}  // close anonymous namespace

// ----------------------------------------------------------------------------

static RegisterCheck c1(check_name, &conversions);

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
