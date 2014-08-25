// csamisc_memberdefinitioninclassdefinition.cpp                      -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/DeclCXX.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <llvm/Support/Casting.h>
#include <map>
#include <string>

using namespace clang;
using namespace csabase;

// -----------------------------------------------------------------------------

static std::string const check_name("member-definition-in-class-definition");

// -----------------------------------------------------------------------------

namespace
{
    struct member_definition
    {
        std::map<void const*, bool> reported_;
    };
}

// -----------------------------------------------------------------------------

static void
member_definition_in_class_definition(Analyser& analyser,
                                      CXXMethodDecl const* decl)
{
    member_definition& data = analyser.attachment<member_definition>();

    if (decl->isTemplateInstantiation()) {
        if (CXXMethodDecl const* tplt = llvm::dyn_cast<CXXMethodDecl>(
                decl->getTemplateInstantiationPattern())) {
            decl = tplt;
        }
    }

    if (decl->getLexicalDeclContext() == decl->getDeclContext()
        && decl->hasInlineBody()
        && !decl->getParent()->isLocalClass()
        && !decl->isImplicit()
        && !data.reported_[decl->getCanonicalDecl()]
        && !analyser.is_test_driver()
        && !decl->getLocStart().isMacroID())
    {
        analyser.report(decl, check_name, "CD01",
                "Member function '%0' is defined in the class definition.")
            << decl->getQualifiedNameAsString();
        data.reported_[decl->getCanonicalDecl()] = true;
    }
}

// -----------------------------------------------------------------------------

static RegisterCheck check(check_name, &member_definition_in_class_definition);

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
