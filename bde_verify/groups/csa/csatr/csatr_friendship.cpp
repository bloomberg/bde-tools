// csatr_friendship.cpp                                               -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/DeclBase.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/DeclFriend.h>
#include <clang/AST/DeclTemplate.h>
#include <clang/AST/TemplateName.h>
#include <clang/AST/Type.h>
#include <clang/AST/TypeLoc.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_format.h>
#include <csabase_location.h>
#include <csabase_registercheck.h>
#include <llvm/Support/Casting.h>
#include <string>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("local-friendship-only");

// ----------------------------------------------------------------------------

static bool is_extern_type(Analyser& analyser, Type const* type)
{
    CXXRecordDecl const* record(type->getAsCXXRecordDecl());
    Location cloc(analyser.get_location(record));
    return (type->isIncompleteType()
            && record->getLexicalDeclContext()->isFileContext())
        || !analyser.is_component(cloc.file());
}

// ----------------------------------------------------------------------------

static void local_friendship_only(Analyser& analyser, FriendDecl const* decl)
{
    const NamedDecl *named = decl->getFriendDecl();
    const TypeSourceInfo *tsi = decl->getFriendType();
    const Type *type = tsi ? tsi->getTypeLoc().getTypePtr() : 0;
    if (type && type->isElaboratedTypeSpecifier()) {
        type = type->getAs<ElaboratedType>()->getNamedType().getTypePtr();
        if (const TemplateSpecializationType* spec =
                type->getAs<TemplateSpecializationType>()) {
            named = spec->getTemplateName().getAsTemplateDecl();
        }
    }

    if (named) {
        if (CXXMethodDecl const* method
            = llvm::dyn_cast<CXXMethodDecl>(named)) {
            if (!analyser.is_component(method->getParent())) {
                analyser.report(decl->getFriendLoc(), check_name, "TR19",
                                "Friendship to a method "
                                "can only be granted within a component")
                    << decl->getSourceRange();
            }
        }
        else if (FunctionDecl const* function
                 = llvm::dyn_cast<FunctionDecl>(named)) {
            if (!analyser.is_component(function->getCanonicalDecl())) {
                analyser.report(decl->getFriendLoc(), check_name, "TR19",
                                "Friendship to a function "
                                "can only be granted within a component")
                    << decl->getSourceRange();
            }
        }
        else if (FunctionTemplateDecl const* function
                 = llvm::dyn_cast<FunctionTemplateDecl>(named)) {
            if (!analyser.is_component(function->getCanonicalDecl())) {
                analyser.report(decl->getFriendLoc(), check_name,  "TR19",
                                "Friendship to a function template "
                                "can only be granted within a component")
                    << decl->getSourceRange();
            }
        }
        else if (ClassTemplateDecl const* cls
                 = llvm::dyn_cast<ClassTemplateDecl>(named)) {
            if (!analyser.is_component(cls->getCanonicalDecl())) {
                analyser.report(decl->getFriendLoc(), check_name, "TR19",
                                "Friendship to a class template "
                                "can only be granted within a component")
                    << decl->getSourceRange();
            }
        }
        else {
            analyser.report(decl, check_name,  "TR19",
                            "Unknonwn kind of friendship (%0)")
                << decl->getSourceRange()
                << format(named->getKind());
        }
    }
    else {
        TypeSourceInfo const* typeInfo(decl->getFriendType());
        TypeLoc loc(typeInfo->getTypeLoc());
        Type const* type(loc.getTypePtr());
        if (is_extern_type(analyser, type)) {
            analyser.report(decl, check_name, "TR19",
                            "Friendship to a class "
                            "can only be granted within a component"
                            )
                << decl->getSourceRange();
        }
    }
}

// ----------------------------------------------------------------------------

static RegisterCheck check(check_name, &local_friendship_only);

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
