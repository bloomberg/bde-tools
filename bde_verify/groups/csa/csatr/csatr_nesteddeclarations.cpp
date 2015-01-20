// csatr_nesteddeclarations.cpp                                       -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/DeclBase.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/DeclTemplate.h>
#include <clang/AST/Type.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_cast_ptr.h>
#include <csabase_config.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_location.h>
#include <csabase_registercheck.h>
#include <csabase_util.h>
#include <llvm/Support/Casting.h>
#include <string>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("nested-declarations");

// ----------------------------------------------------------------------------

static bool is_swap(FunctionDecl const* decl)
{
    return decl->getNameAsString() == "swap" && decl->getNumParams() == 2 &&
           decl->getParamDecl(0)->getType() ==
               decl->getParamDecl(1)->getType() &&
           decl->getParamDecl(0)->getType().getTypePtr()->isReferenceType() &&
           !decl->getParamDecl(0)
                ->getType()
                .getNonReferenceType()
                .isConstQualified();
}

// ----------------------------------------------------------------------------

static bool isSpecialFunction(NamedDecl const* decl)
{
    cast_ptr<FunctionDecl> function(decl);
    return function
        && (function->isOverloadedOperator() || is_swap(function.get()));
}

// ----------------------------------------------------------------------------

static void check(Analyser& analyser, Decl const* decl)
{
    if (analyser.is_main() &&
        analyser.config()->value("main_namespace_check") == "off") {
        return;                                                       // RETURN
    }

    if (analyser.is_global_package()) {
        return;                                                       // RETURN
    }

    Location location(analyser.get_location(decl));
    NamedDecl const* named(llvm::dyn_cast<NamedDecl>(decl));
    if (analyser.is_component(location.file()) && named) {
        if (llvm::dyn_cast<NamespaceDecl>(decl)
            || llvm::dyn_cast<UsingDirectiveDecl>(decl)) {
            // namespace declarations are permissible e.g. for forward
            // declarations.
            return;                                                   // RETURN
        }
        else if (TagDecl const* tag = llvm::dyn_cast<TagDecl>(decl)) {
            // Forward declarations are always permissible but definitions are
            // not.
            if (!tag->isThisDeclarationADefinition()
                && analyser.is_component_header(location.file())) {
                return;                                               // RETURN
            }
        }
        else if (llvm::dyn_cast<NamespaceAliasDecl>(decl)
                 && analyser.is_component_source(decl)) {
            return;                                                   // RETURN
        }

        DeclContext const* context(decl->getDeclContext());
        std::string name = named->getNameAsString();
        if (llvm::dyn_cast<TranslationUnitDecl>(context)) {
            if (name != "main" &&
                name != "RCSId" &&
                !llvm::dyn_cast<ClassTemplateSpecializationDecl>(decl) &&
                !llvm::dyn_cast<ClassTemplatePartialSpecializationDecl>(
                    decl) &&
                name.find("operator new") == std::string::npos &&
                name.find("operator delete") == std::string::npos &&
                (analyser.is_component_header(location.file()) ||
                 named->isExternallyVisible/*hasLinkage*/())) {
                analyser.report(decl, check_name, "TR04",
                                "Declaration of '%0' at global scope", true)
                    << decl->getSourceRange()
                    << name;
            }
            return;                                                   // RETURN
        }

        NamespaceDecl const* space =
            llvm::dyn_cast<NamespaceDecl>(context);
        if (!space) {
            return;                                                   // RETURN
        }

        std::string pkgns = analyser.package();
        if (   space->isAnonymousNamespace()
            && llvm::dyn_cast<NamespaceDecl>(space->getDeclContext())) {
            space =
                llvm::dyn_cast<NamespaceDecl>(space->getDeclContext());
        }
        if (space->getNameAsString() ==
            analyser.config()->toplevel_namespace()) {
            // No package namespace.  This is OK if no package namespace has
            // been seen, for the sake of legacy "package_name" components.
            DeclContext::decl_iterator b = space->decls_begin();
            DeclContext::decl_iterator e = space->decls_end();
            bool found = false;
            while (!found && b != e) {
                const NamespaceDecl *ns =
                    llvm::dyn_cast<NamespaceDecl>(*b++);
                found = ns && ns->getNameAsString() == analyser.package();
            }
            if (!found) {
                pkgns = analyser.config()->toplevel_namespace();
            }
        }
        if (name.length() > 0)
        {
            std::string spname = space->getNameAsString();
            NamespaceDecl const* outer = space;
            if (pkgns == analyser.package()) {
                outer = llvm::dyn_cast<NamespaceDecl>(
                    space->getDeclContext());
            }
            if ((spname != pkgns
                 || !outer
                 || outer->getNameAsString() !=
                    analyser.config()->toplevel_namespace())
                && (   spname != analyser.config()->toplevel_namespace()
                    || name.find(analyser.package() + '_') != 0
                    )
                && to_lower(spname) != to_lower(analyser.component())
                && !llvm::dyn_cast<ClassTemplateSpecializationDecl>(decl)
                && !llvm::dyn_cast<ClassTemplatePartialSpecializationDecl>(decl)
                && name.find("operator new") == std::string::npos
                && name.find("operator delete") == std::string::npos
                && !isSpecialFunction(named)
                && (   analyser.is_component_header(named)
                    || named->hasLinkage()
                    )
                && !analyser.is_ADL_candidate(decl)
                )
            {
                //-dk:TODO check if this happens in the correct namespace
                analyser.report(decl, check_name, "TR04",
                    "Declaration of '%0' not within package namespace '%1'",
                    true)
                    << decl->getSourceRange()
                    << name
                    << (analyser.config()->toplevel_namespace() + "::" + analyser.package())
                    ;
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
