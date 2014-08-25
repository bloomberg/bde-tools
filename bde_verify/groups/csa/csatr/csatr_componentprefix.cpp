// csatr_componentprefix.cpp                                          -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/DeclBase.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/DeclTemplate.h>
#include <csabase_analyser.h>
#include <csabase_config.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <csabase_util.h>
#include <llvm/Support/Casting.h>
#include <string>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("component-prefix");

// ----------------------------------------------------------------------------

static bool wrong_prefix(Analyser& analyser, const NamedDecl* named)
{
    std::string package_prefix = analyser.package() + "_";
    std::string name = named->getNameAsString();
    if (name.find(package_prefix) != 0) {
        name = package_prefix + name;
    }
    return 0 != to_lower(name).find(analyser.component()) &&
           0 != to_lower(named->getQualifiedNameAsString())
                    .find(to_lower(
                         analyser.config()->toplevel_namespace() + "::" +
                         analyser.component() + "::"));
}

// ----------------------------------------------------------------------------

static void
component_prefix(Analyser&  analyser,
                 Decl const        *decl)
{
    const DeclContext *dc = decl->getDeclContext();
    if (dc->isClosure() || dc->isFunctionOrMethod() || dc->isRecord()) {
        return;                                                       // RETURN
    }

    NamedDecl const* named(llvm::dyn_cast<NamedDecl>(decl));
    FunctionDecl const* fd = llvm::dyn_cast<FunctionDecl>(decl);
    if (FunctionTemplateDecl const* ftd =
            llvm::dyn_cast<FunctionTemplateDecl>(decl)) {
        fd = ftd->getTemplatedDecl();
    }
    std::string const& name(named ? named->getNameAsString() : std::string());
    if (   !name.empty()
        && !analyser.is_global_package()
        && !named->isCXXClassMember()
        && (   named->hasLinkage()
            || (   llvm::dyn_cast<TypedefDecl>(named)
                && name.find(analyser.package() + "_") != 0
               ))
        && !llvm::dyn_cast<NamespaceDecl>(named)
        && !llvm::dyn_cast<UsingDirectiveDecl>(named)
        && !llvm::dyn_cast<UsingDecl>(named)
        && analyser.is_component_header(decl)
        && wrong_prefix(analyser, named)
        && (!llvm::dyn_cast<RecordDecl>(named)
            || llvm::dyn_cast<RecordDecl>(named)->isCompleteDefinition()
            )
        && (   !fd
            || (!fd->isOverloadedOperator()
                 && name != "swap"
                 && name != "debugprint"
                 && !analyser.is_ADL_candidate(fd))
            )
        && !llvm::dyn_cast<ClassTemplateSpecializationDecl>(decl)
        && !llvm::dyn_cast<ClassTemplatePartialSpecializationDecl>(decl)
        && !(   llvm::dyn_cast<CXXRecordDecl>(decl)
             && llvm::dyn_cast<CXXRecordDecl>(decl)->
                                                   getDescribedClassTemplate())
        ) {
        analyser.report(decl, check_name, "CP01",
                        "Globally visible identifier '%0' "
                        "without component prefix")
            << named->getQualifiedNameAsString();
    }
}

// ----------------------------------------------------------------------------

static RegisterCheck check(check_name, &component_prefix);

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
