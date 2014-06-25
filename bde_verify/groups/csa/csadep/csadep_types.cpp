// csadep_types.cpp                                                   -*-C++-*-

#include <csadep_dependencies.h>

#include <csabase_analyser.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <csabase_location.h>
#include <csabase_format.h>
#include <csabase_cast_ptr.h>
#include <algorithm>
#include <map>
#include <set>
#include <sstream>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("include_files");

// ----------------------------------------------------------------------------

static void record_needed_declaration(Analyser& analyser,
                                      Decl const* decl,
                                      NamedDecl const* named,
                                      bool need_definition,
                                      bool print = true)
{
    // print = true;
    if (print) {
        SourceLocation location(decl->getLocStart());
        analyser.report(location, check_name, "??IF01",
                "In file %2 need %0 for %1")
            << (need_definition? "definition": "declaration")
            << named->getQualifiedNameAsString()
            << analyser.get_location(decl).file()
            ;
    }
    bde_verify::csadep::dependencies&
        deps(analyser.attachment<bde_verify::csadep::dependencies>());
    deps.add(analyser.get_location(decl).file(),
             decl->getLocStart(),
             need_definition,
             named);
}
                      
// -----------------------------------------------------------------------------
// check_type() determines what sort of declaration is needed for
// the passed type. The kind of declaration may depend on whether
// the type is used in a declaraton or in a definition and the
// inDefinition flag indicates whether the type is used in a
// definition.

static void check_type(Analyser& analyser,
                       Decl const* decl,
                       Type const* type,
                       bool inDefinition,
                       bool print = false)
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
        break;
    case Type::Pointer:
        {
            cast_ptr<PointerType> const pointer(type);
            check_type(analyser, decl, pointer->getPointeeType().getTypePtr(), false, print);
        }
        break;
    case Type::LValueReference:
    case Type::RValueReference:
        {
            cast_ptr<ReferenceType> const reference(type);
            check_type(analyser, decl, reference->getPointeeType().getTypePtr(), false, print);
        }
        break;
    case Type::MemberPointer:
        {
            cast_ptr<MemberPointerType> const member(type);
            check_type(analyser, decl, member->getPointeeType().getTypePtr(), false, print);
            check_type(analyser, decl, member->getClass(), false, print);
        }
        break;
    case Type::ConstantArray:
        {
            cast_ptr<ConstantArrayType> const array(type);
            check_type(analyser, decl, array->getElementType().getTypePtr(), inDefinition, print);
            //-dk:TODO check where the size is coming from!
        }
        break;
    case Type::IncompleteArray:
        {
            cast_ptr<IncompleteArrayType> const array(type);
            check_type(analyser, decl, array->getElementType().getTypePtr(), inDefinition, print);
        }
        break;
    case Type::VariableArray:
        break; // variable sized arrays are not part of C++
    case Type::DependentSizedArray:
        break; // these need to be checked during instantiation
    case Type::DependentSizedExtVector:
    case Type::Vector:
    case Type::ExtVector:
        break; // SIMD vectors are not part of standard C++
    case Type::FunctionProto: // fall through
    case Type::FunctionNoProto:
        analyser.report(decl, check_name, "??FP01", "TODO: function proto");
        break;
    case Type::UnresolvedUsing:
        break; // these need to be checked during instantiation
    case Type::Paren:
        {
            cast_ptr<ParenType> const paren(type);
            check_type(analyser, decl, paren->getInnerType().getTypePtr(), inDefinition, print);
        }
        break;
    case Type::Typedef:
        {
            cast_ptr<TypedefType> const typeDef(type);
            if (inDefinition) {
                check_type(analyser, decl,
                           typeDef->getDecl()->getUnderlyingType().getTypePtr(), true, print);
            }
            record_needed_declaration(analyser, decl, typeDef->getDecl(), true, print);
        }
        break;
    case Type::Decltype:
        break; // these become available with C++2011 only
    case Type::Record:
        {
            cast_ptr<RecordType> const record(type);
            record_needed_declaration(analyser, decl, record->getDecl(), inDefinition, print);
        }
        break;
    case Type::Enum:
        {
            cast_ptr<EnumType> const enumType(type);
            record_needed_declaration(analyser, decl, enumType->getDecl(), true, print);
        }
        break;
    case Type::Elaborated:
        {
            cast_ptr<ElaboratedType> const elaborated(type);
            check_type(analyser, decl, elaborated->getNamedType().getTypePtr(), inDefinition, print);
        }
        break;
    case Type::SubstTemplateTypeParm:
        {
            cast_ptr<SubstTemplateTypeParmType> const subst(type);
            check_type(analyser, decl, subst->getReplacementType().getTypePtr(), inDefinition, print);
        }
        break;
    case Type::Attributed:
        break; // attributed types are not part of standard C++
    case Type::TemplateTypeParm:
        break; // these need to be checked during instantiation
    case Type::SubstTemplateTypeParmPack:
        break; // these become available with C++2011 only
    case Type::TemplateSpecialization:
        {
            cast_ptr<TemplateSpecializationType> templ(type);
            record_needed_declaration(analyser, decl, templ->getTemplateName().getAsTemplateDecl(), inDefinition, print);
            for (TemplateSpecializationType::iterator it(templ->begin()), end(templ->end()); it != end; ++it)
            {
                if (it->getKind() == TemplateArgument::Type)
                {
                    check_type(analyser, decl, it->getAsType().getTypePtr(), inDefinition, print);
                }
            }
        }
        break;
    case Type::Auto:
        break; // these become available with C++2011 only
    case Type::InjectedClassName:
        {
            cast_ptr<InjectedClassNameType> injected(type);
            check_type(analyser, decl, injected->getInjectedSpecializationType().getTypePtr(), inDefinition, print);
        }
        break;
    case Type::DependentName:
        break; // these need to be checked during instantiation
    case Type::DependentTemplateSpecialization:
        break; // these need to be checked during instantiation
    case Type::PackExpansion:
        break; // these become available with C++2011 only
    default:
        analyser.report(decl, check_name, "??UT01",
                "Unknown type class: %0")
            << format(type->getTypeClass());
        break;
    }
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

static void
on_include(Analyser& analyser, std::string const& from, std::string const& file)
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

static void
on_open(Analyser& analyser, SourceLocation, std::string const& from, std::string const& file)
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
        for (CXXRecordDecl::base_class_const_iterator it(decl->bases_begin()), end(decl->bases_end()); it != end; ++it)
        {
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
    for (FunctionDecl::param_const_iterator it(decl->param_begin()), end(decl->param_end()); it != end; ++it)
    {
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

namespace
{
    struct binder
    {
        binder(void (*function)(Analyser&, SourceLocation, std::string const&, std::string const&),
               Analyser& analyser):
            function_(function),
            analyser_(&analyser)
        {
        }
        void
        operator()(SourceLocation location, std::string const& from, std::string const& file) const
        {
            (*function_)(*analyser_, location, from, file);
        }
        void          (*function_)(Analyser&, SourceLocation, std::string const&, std::string const&);
        Analyser* analyser_;
    };
}

namespace
{
    struct skip_binder
    {
        skip_binder(void (*function)(Analyser&, std::string const&, std::string const&), Analyser& analyser):
            function_(function),
            analyser_(&analyser)
        {
        }
        void
        operator()(std::string const& from, std::string const& file)
        {
            (*function_)(*analyser_, from, file);
        }
        void          (*function_)(Analyser&, std::string const&, std::string const&);
        Analyser* analyser_;
    };
}

static void
subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
{
    observer.onOpenFile += binder(on_open, analyser);
    observer.onSkipFile += skip_binder(on_skip, analyser);
}

// -----------------------------------------------------------------------------

static RegisterCheck register_check0(check_name, &on_decl);
static RegisterCheck register_check1(check_name, &on_cxxrecorddecl);
static RegisterCheck register_check3(check_name, &on_functiondecl);
static RegisterCheck register_check4(check_name, &on_expr);
static RegisterCheck register_observer(check_name, &subscribe);
static void
on_declref(Analyser& analyser, DeclRefExpr const* expr)
{
    ValueDecl const* decl(expr->getDecl());
    analyser.report(decl, check_name, "declaration")
        << decl->getSourceRange()
        ;
    analyser.report(expr, check_name, "declref")
        << expr->getSourceRange()
        ;
}
static RegisterCheck register_check0(check_name, &on_declref);
#else
// -----------------------------------------------------------------------------

static void on_valuedecl(Analyser& analyser, VarDecl const* decl)
{
    check_type(analyser, decl, decl->getType().getTypePtr(),
                 !decl->hasExternalStorage());
}

// -----------------------------------------------------------------------------

static void on_typedefdecl(Analyser& analyser, TypedefDecl const* decl)
{
    check_type(analyser, decl, decl->getUnderlyingType().getTypePtr(), false);
}

// -----------------------------------------------------------------------------

static RegisterCheck register_check_typedefdecl(check_name, &on_typedefdecl);
static RegisterCheck register_check_valuedecl(check_name, &on_valuedecl);
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
