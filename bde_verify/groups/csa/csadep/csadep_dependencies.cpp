// csadep_dependencies.cpp                                            -*-C++-*-

#include <csadep_dependencies.h>
#include <clang/AST/Decl.h>
#include <llvm/Support/raw_ostream.h>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

bde_verify::csadep::dependencies::dependency::dependency(
    SourceLocation const& location,
    bool need_definition,
    NamedDecl const* decl)
: d_location(location)
, d_need_definition(need_definition)
, d_decl(decl)
{
}

// ----------------------------------------------------------------------------

void bde_verify::csadep::dependencies::add(std::string const& source,
                                           SourceLocation const& location,
                                           bool need_definition,
                                           NamedDecl const* decl)
{
    typedef container::iterator iterator;

    std::string name(decl->getQualifiedNameAsString());

    llvm::errs() << "add(" << source << ", loc, "
                 << (need_definition? "definition": "declaration") << ", "
                 << name << ")\n";
    container& decls = d_sources[source];
    iterator it(
        decls.insert(std::make_pair(
                         std::string(name),
                         dependency(location, need_definition, decl))).first);
    if (need_definition) {
        it->second.d_need_definition = true;
    }
}

// ----------------------------------------------------------------------------

static std::map<std::string,
                bde_verify::csadep::dependencies::dependency> const s_empty;

std::pair<bde_verify::csadep::dependencies::const_iterator,
          bde_verify::csadep::dependencies::const_iterator>
bde_verify::csadep::dependencies::get_referenced(std::string const& source)
    const
{
    return std::make_pair(s_empty.begin(), s_empty.end());
}

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
