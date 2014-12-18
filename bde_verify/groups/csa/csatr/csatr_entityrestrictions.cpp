// csatr_entityrestrictions.cpp                                       -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/DeclarationName.h>
#include <clang/AST/Type.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_config.h>
#include <csabase_debug.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/Support/Casting.h>
#include <llvm/Support/Regex.h>
#include <string>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("entity-restrictions");

// ----------------------------------------------------------------------------

static bool is_global_name(Analyser& analyser, NamedDecl const *decl)
{
    llvm::Regex re("(^ *|[^[:alnum:]])" +
                   decl->getNameAsString() +
                   "([^[:alnum:]]| *$)");
    return re.match(
        analyser.config()->value("global_names", decl->getLocation()));
}

// ----------------------------------------------------------------------------

static void enum_declaration(Analyser& analyser, EnumDecl const* decl)
{
    if (   decl->getDeclContext()->isFileContext()
        && !is_global_name(analyser, decl)
        && !decl->getLocation().isMacroID()
        && analyser.is_component_header(decl)
        && !analyser.is_standard_namespace(decl->getQualifiedNameAsString())) {
        analyser.report(decl, check_name, "TR17",
                        "Enum '%0' declared at global scope")
            << decl->getName();
    }
}

// ----------------------------------------------------------------------------

static void var_declaration(Analyser& analyser, VarDecl const* decl)
{
    if (   decl->getDeclContext()->isFileContext()
        && !is_global_name(analyser, decl)
        && !decl->getLocation().isMacroID()
        && analyser.is_component_header(decl)
        && !analyser.is_standard_namespace(decl->getQualifiedNameAsString())) {
        analyser.report(decl, check_name, "TR17",
                        "Variable '%0' declared at global scope")
            << decl->getName();
    }
}

// ----------------------------------------------------------------------------

static bool
is_swap(FunctionDecl const* decl)
{
    return decl->getNameAsString() == "swap"
        && decl->getNumParams() == 2
        && decl->getParamDecl(0)->getType()->getCanonicalTypeInternal() ==
           decl->getParamDecl(1)->getType()->getCanonicalTypeInternal()
        && decl->getParamDecl(0)->getType().getTypePtr()->isReferenceType()
        && !decl->getParamDecl(0)->getType().getNonReferenceType()
                .isConstQualified();
}

static void function_declaration(Analyser& analyser, FunctionDecl const* decl)
{
    if (   decl->getDeclContext()->isFileContext()
        && !is_global_name(analyser, decl)
        && !decl->getLocation().isMacroID()
        && analyser.is_component_header(decl)
        && !decl->isOverloadedOperator()
        && !is_swap(decl)
        && decl->getNameAsString() != "debugprint"
        && decl->isFirstDecl()
        && !analyser.is_ADL_candidate(decl)
        && !analyser.is_standard_namespace(decl->getQualifiedNameAsString())
        ) {
        analyser.report(decl, check_name, "TR17",
                        "Function '%0' declared at global scope")
            << decl->getNameAsString()
            << decl->getNameInfo().getSourceRange();
    }
}

// -----------------------------------------------------------------------------

static void typedef_declaration(Analyser& analyser, TypedefDecl const* decl)
{
    // Allow global scope typedef to a name that begins with "package_" for
    // legacy support of "typedef package::name package_name;".
    std::string package = analyser.package() + "_";
    if (package.find("bslfwd_") == 0) {
        package = package.substr(7);
    }
    if (   decl->getDeclContext()->isFileContext()
        && !is_global_name(analyser, decl)
        && !decl->getLocation().isMacroID()
        && analyser.is_component_header(decl)
        && decl->getNameAsString().find(package) != 0
        && !analyser.is_standard_namespace(decl->getQualifiedNameAsString())
        ) {
        analyser.report(decl, check_name, "TR17",
                        "Typedef '%0' declared at global scope")
            << decl->getNameAsString();
    }
}

// -----------------------------------------------------------------------------

static RegisterCheck c0(check_name, &enum_declaration);
static RegisterCheck c1(check_name, &var_declaration);
static RegisterCheck c2(check_name, &function_declaration);
static RegisterCheck c3(check_name, &typedef_declaration);

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
