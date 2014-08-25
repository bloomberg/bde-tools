// csadep_dependencies.h                                              -*-C++-*-

#ifndef INCLUDED_CSADEP_DEPENDENCIES
#define INCLUDED_CSADEP_DEPENDENCIES

#include <clang/Basic/SourceLocation.h>
#include <string>
#include <map>
#include <utility>

// ----------------------------------------------------------------------------

namespace clang { class NamedDecl; }

namespace bde_verify
{
namespace csadep
{
class dependencies
{
public:
    struct dependency
    {
        dependency(clang::SourceLocation const& location,
                   bool                         need_definition,
                   clang::NamedDecl const*      decl);

        clang::SourceLocation   d_location;
        bool                    d_need_definition;
        clang::NamedDecl const* d_decl;
    };
    typedef std::map<std::string, dependency> container;
    typedef container::const_iterator         const_iterator;

private:
    std::map<std::string, container> d_sources;

public:
    void add(std::string const&           source,
             clang::SourceLocation const& location,
             bool                         need_definition,
             clang::NamedDecl const*      decl);

    std::pair<const_iterator, const_iterator>
        get_referenced(std::string const& source) const;
};
}
}

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
