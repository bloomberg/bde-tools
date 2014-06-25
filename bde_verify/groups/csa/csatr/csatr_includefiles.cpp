// csatr_includefiles.cpp                                             -*-C++-*-

#include <csabase_analyser.h>
#include <csabase_binder.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <csabase_location.h>
#include <csabase_format.h>
#include <algorithm>
#include <map>
#include <set>
#include <sstream>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("include_files");

// -----------------------------------------------------------------------------

static bool check_type(Analyser& analyser, Decl const* decl, Type const* type)
    // check_type() determines if the type argument needs a declaration.  If
    // so, it returns true.
{
    switch (type->getTypeClass())
    {
    case Type::Builtin:           // Built-in types are alwyas there.
    case Type::Complex:           // C-style complex not in C++.
    case Type::BlockPointer:      // don't know what these are...
    case Type::ObjCObject:        // don't care about Objective C
    case Type::ObjCInterface:     // don't care about Objective C
    case Type::ObjCObjectPointer: // don't care about Objective C
    case Type::TypeOfExpr:        // gcc extension
    case Type::TypeOf:            // gcc extension
        return false;
    case Type::Pointer:
        check_type(
            analyser,
            decl,
            llvm::dyn_cast<PointerType>(type)->getPointeeType().getTypePtr());
        break;
    case Type::LValueReference:
    case Type::RValueReference:
        check_type(analyser,
                   decl,
                   llvm::dyn_cast<ReferenceType>(type)
                       ->getPointeeType()
                       .getTypePtr());
        break;
    case Type::MemberPointer: {
        MemberPointerType const* member(
            llvm::dyn_cast<MemberPointerType>(type));
        check_type(analyser, decl, member->getPointeeType().getTypePtr());
        check_type(analyser, decl, member->getClass());
    } break;
    case Type::ConstantArray: {
        ConstantArrayType const* array(
            llvm::dyn_cast<ConstantArrayType>(type));
        check_type(analyser, decl, array->getElementType().getTypePtr());
        //-dk:TODO check where the size is coming from!
    } break;
    case Type::IncompleteArray:
        check_type(analyser,
                   decl,
                   llvm::dyn_cast<IncompleteArrayType>(type)
                       ->getElementType()
                       .getTypePtr());
        break;
    case Type::VariableArray: {
        VariableArrayType const* array(
            llvm::dyn_cast<VariableArrayType>(type));
        check_type(analyser, decl, array->getElementType().getTypePtr());
        //-dk:TODO check_expr(analyser, decl, array->getSizeExpr());
    } break;
    case Type::DependentSizedArray: {
        DependentSizedArrayType const* array(
            llvm::dyn_cast<DependentSizedArrayType>(type));
        check_type(analyser, decl, array->getElementType().getTypePtr());
        //-dk:TODO check_expr(analyser, decl, array->getSizeExpr());
    } break;
    case Type::DependentSizedExtVector:
    case Type::Vector:
    case Type::ExtVector:
        break; //-dk:TODO
    case Type::FunctionProto: // fall through
    case Type::FunctionNoProto: {
        FunctionType const* function(llvm::dyn_cast<FunctionType>(type));
        check_type(analyser, decl, function->getResultType().getTypePtr());
    } break;
    case Type::UnresolvedUsing:
        break; //-dk:TODO
    case Type::Paren:
        check_type(
            analyser,
            decl,
            llvm::dyn_cast<ParenType>(type)->getInnerType().getTypePtr());
        break;
    case Type::Typedef:
        //-dk:TODO check_declref(analyser, decl,
        //llvm::dyn_cast<TypedefType>(type)->getDecl());
        break;
    case Type::Decltype:
        break; //-dk:TODO C++0x
    case Type::Record: // fall through
    case Type::Enum:
        analyser.report(decl, check_name, "CT01", "Enum");
        //-dk:TODO check_declref(analyser, decl,
        //llvm::dyn_cast<TagType>(type)->getDecl());
        break;
    case Type::Elaborated:
        check_type(
            analyser,
            decl,
            llvm::dyn_cast<ElaboratedType>(type)->getNamedType().getTypePtr());
        break;
    case Type::SubstTemplateTypeParm:
        break;  // the substituted template type parameter needs to be already
                // declared
    case Type::Attributed:
    case Type::TemplateTypeParm:
    case Type::SubstTemplateTypeParmPack:
        analyser.report(decl, check_name, "CT01", "TODO type class: %0")
            << format(type->getTypeClass());
        break;
    case Type::TemplateSpecialization: {
        TemplateSpecializationType const* templ(
            llvm::dyn_cast<TemplateSpecializationType>(type));
        //-dk:TODO check_declref(analyser, decl,
        //templ->getTemplateName().getAsTemplateDecl());
        for (TemplateSpecializationType::iterator it(templ->begin()),
             end(templ->end());
             it != end;
             ++it) {
            if (it->getKind() == TemplateArgument::Type) {
                check_type(analyser, decl, it->getAsType().getTypePtr());
            }
        }
    } break;
    case Type::Auto:
    case Type::InjectedClassName:
    case Type::DependentName:
    case Type::DependentTemplateSpecialization:
    case Type::PackExpansion:
        analyser.report(decl, check_name, "CT01", "TODO type class: %0")
            << format(type->getTypeClass());
        break;
        break; // don't care about objective C
    default:
        analyser.report(decl, check_name, "CT01", "Unknown type class: %0")
            << format(type->getTypeClass());
        break;
    }

    return true;
}

// -----------------------------------------------------------------------------

#if 0
namespace
{
    struct include_files
    {
        std::map<std::string, std::set<std::string> >  includes_;
        std::set<std::pair<std::string, std::string> > reported_;
    };
}

// -----------------------------------------------------------------------------

static void on_include(Analyser& analyser,
                       std::string const& from,
                       std::string const& file)
{
    include_files& context(analyser.attachment<include_files>());
    context.includes_[from].insert(file);
    if (analyser.is_component_header(from))
    {
        context.includes_[analyser.toplevel()].insert(file);
    }
    //llvm::errs() << "on_include(" << from << ", " << file << ")\n";
}

// -----------------------------------------------------------------------------

static void on_open(Analyser& analyser,
                    SourceLocation,
                    std::string const& from,
                    std::string const& file)
{
    on_include(analyser, from, file);
}

static void
on_skip(Analyser& analyser, std::string const& from, std::string const& file)
{
    on_include(analyser, from, file);
}

// -----------------------------------------------------------------------------

static void
check_declref(Analyser& analyser, Decl const* decl, Decl const* declref)
{
    std::string const& file(analyser.get_location(decl).file());
    include_files& context(analyser.attachment<include_files>());
    std::set<std::string> const& includes(context.includes_[file]);

    analyser.report(declref, check_name, "declref")
        << declref
        ;
    std::string header(analyser.get_location(declref).file());
    if (file != header
        && includes.find(header) == includes.end()
        // && context.reported_.insert(std::make_pair(file, header)).second
        )
    {
        analyser.report(decl, check_name,
                        "header file '%0' only included indirectly!")
            << header;
    }
}

// -----------------------------------------------------------------------------

static void
on_cxxrecorddecl(Analyser& analyser, CXXRecordDecl const* decl)
{
    if (decl->hasDefinition())
    {
        for (CXXRecordDecl::base_class_const_iterator it(decl->bases_begin()),
             end(decl->bases_end());
             it != end;
             ++it) {
            CXXRecordDecl* record(it->getType()->getAsCXXRecordDecl());
            if (record)
            {
                check_declref(analyser, decl, record);
            }
        }
    }
}

// -----------------------------------------------------------------------------

static void
check_expr(Analyser& analyser, Decl const* decl, Expr const* expr)
{
    //-dk:TODO
}

// -----------------------------------------------------------------------------

static void
check_type(Analyser& analyser, Decl const* decl, Type const* type);

static void
check_type(Analyser& analyser, Decl const* decl, QualType qual_type)
{
    if (Type const* type = qual_type.getTypePtrOrNull())
    {
        check_type(analyser, decl, type);
    }
}

// -----------------------------------------------------------------------------

static void
on_functiondecl(Analyser& analyser, FunctionDecl const* decl)
{
    for (FunctionDecl::param_const_iterator it(decl->param_begin()),
         end(decl->param_end());
         it != end;
         ++it) {
        ParmVarDecl const* parameter(*it);
        check_type(analyser, parameter, parameter->getType());
        if (parameter->getDefaultArg())
        {
            check_expr(analyser, decl, parameter->getDefaultArg());
        }
    }
}

// -----------------------------------------------------------------------------

static void
on_decl(Analyser& analyser, Decl const* decl)
{
#if 0
    NamedDecl const* named(llvm::dyn_cast<NamedDecl>(decl));
    llvm::errs() << "on_decl " << (named? named->getNameAsString(): "") << " "
                 << "loc=" << analyser.get_location(decl) << " "
                 << "\n";
#endif
}

// -----------------------------------------------------------------------------

static void
on_expr(Analyser& analyser, Expr const* expr)
{
    //-dk:TODO analyser.report(expr, check_name, "expr");
}

// -----------------------------------------------------------------------------

static void
subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
{
    observer.onOpenFile += bind<Analyser&>(analyser, on_open);
    observer.onSkipFile += bind<Analyser&>(analyser, on_skip);
}

// -----------------------------------------------------------------------------

static RegisterCheck register_check0(check_name, &on_decl);
static RegisterCheck register_check1(check_name, &on_cxxrecorddecl);
static RegisterCheck register_check3(check_name, &on_functiondecl);
static RegisterCheck register_check4(check_name, &on_expr);
static RegisterCheck register_observer(check_name, &subscribe);

static void on_declref(Analyser& analyser, DeclRefExpr const* expr)
{
    ValueDecl const* decl(expr->getDecl());
    analyser.report(decl, check_name, "declaration") << decl->getSourceRange();
    analyser.report(expr, check_name, "declref") << expr->getSourceRange();
}

static RegisterCheck register_check0(check_name, &on_declref);
#else
// -----------------------------------------------------------------------------

static void on_valuedecl(Analyser& analyser, DeclaratorDecl const* decl)
{
    if (check_type(analyser, decl, decl->getType().getTypePtr()))
    {
        analyser.report(decl, check_name, "VD01", "Value decl");
    }
}

// -----------------------------------------------------------------------------

static RegisterCheck register_check2(check_name, &on_valuedecl);
#endif

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
