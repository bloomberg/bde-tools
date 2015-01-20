// csabase_format.cpp                                                 -*-C++-*-

#include <csabase_format.h>
#include <clang/AST/Type.h>
#include <clang/AST/Decl.h>
#include <clang/AST/PrettyPrinter.h>
#include <clang/Basic/Diagnostic.h>    // IWYU pragma: keep
#include <clang/Basic/LangOptions.h>
#include <llvm/Support/raw_ostream.h>  // IWYU pragma: keep

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

template <typename Target>
static void printer(Target& out, Type::TypeClass value)
{
    switch (value)
    {
#define TYPE(Class, Base) case Type::Class: out << #Class; break;
#define LAST_TYPE(Class)
#define ABSTRACT_TYPE(Class, Base)
#include "clang/AST/TypeNodes.def"
    default: out << "unknown-type-class=" << value; break;
    }
}

// -----------------------------------------------------------------------------

template <typename Target>
static void printer(Target& out, Decl::Kind value)
{
    switch (value)
    {
#define DECL(Derived, Base) case Decl::Derived: out << #Derived; break;
#define ABSTRACT_DECL(Abstract)
#include "clang/AST/DeclNodes.inc"
    default: out << "unknown-decl-kind=" << value; break;
    }
}

// -----------------------------------------------------------------------------

template <typename Target>
static void printer(Target& out, const NamedDecl *decl)
{
    PrintingPolicy pp{LangOptions()};
    pp.Indentation = 4;
    pp.SuppressSpecifiers = false;
    pp.SuppressTagKeyword = false;
    pp.SuppressTag = false;
    pp.SuppressScope = false;
    pp.SuppressUnwrittenScope = false;
    pp.SuppressInitializers = false;
    pp.ConstantArraySizeAsWritten = true;
    pp.AnonymousTagLocations = true;
    pp.Bool = true;
    pp.TerseOutput = false;
    pp.PolishForDeclaration = true;
    pp.IncludeNewlines = false;

    std::string buf;
    llvm::raw_string_ostream s(buf);
    decl->print(s, pp, 0, true);
    out << s.str();
}

// -----------------------------------------------------------------------------

template <typename T>
void csabase::Formatter<T>::print(llvm::raw_ostream& out) const
{
    printer(out, value_);
}

template <typename T>
void csabase::Formatter<T>::print(DiagnosticBuilder& out) const
{
    printer(out, value_);
}

// -----------------------------------------------------------------------------

template class csabase::Formatter<Type::TypeClass>;
template class csabase::Formatter<Decl::Kind>;
template class csabase::Formatter<const NamedDecl *>;

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
