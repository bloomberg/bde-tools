// csabase_location.h                                                 -*-C++-*-

#ifndef INCLUDED_CSABASE_LOCATION
#define INCLUDED_CSABASE_LOCATION

#include <clang/Basic/SourceLocation.h>
#include <stddef.h>
#include <iosfwd>
#include <string>

namespace clang { class SourceManager; }
namespace llvm { class raw_ostream; }

// -----------------------------------------------------------------------------

namespace csabase
{
class Location
{
private:
    std::string           d_file;
    size_t                d_line;
    size_t                d_column;
    clang::SourceLocation d_location;

public:
    Location();
    Location(clang::SourceManager const& manager,
             clang::SourceLocation location);
    Location(const Location&) = default;
    Location& operator=(const Location&) = default;

    std::string           file() const;
    size_t                line() const;
    size_t                column() const;
    clang::SourceLocation location() const;

    bool operator< (Location const& location) const;
    operator bool() const;
};

llvm::raw_ostream& operator<< (llvm::raw_ostream&, Location const&);
std::ostream& operator<< (std::ostream&, Location const&);
bool operator== (Location const&, Location const&);
bool operator!= (Location const&, Location const&);

class Range
{
private:
    Location d_from;
    Location d_to;

public:
    Range();
    Range(clang::SourceManager const& manager,
          clang::SourceRange range);
    Range(const Range&) = default;
    Range& operator=(const Range&) = default;

    const Location& from() const;
    const Location& to() const;

    bool operator< (Range const& range) const;
    operator bool() const;
};

llvm::raw_ostream& operator<< (llvm::raw_ostream&, Range const&);
std::ostream& operator<< (std::ostream&, Range const&);
bool operator== (Range const&, Range const&);
bool operator!= (Range const&, Range const&);
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
