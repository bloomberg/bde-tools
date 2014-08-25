// csabase_location.cpp                                               -*-C++-*-

#include <csabase_location.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Basic/SourceManager.h>
#include <llvm/Support/raw_ostream.h>
#include <ostream>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

csabase::Location::Location()
    : d_file("<unknown>")
    , d_line(0)
    , d_column(0)
    , d_location()
{
}

csabase::Location::Location(SourceManager const& manager,
                            SourceLocation location)
: d_file()
, d_line(0)
, d_column(0)
, d_location(manager.getExpansionLoc(location))
{
    PresumedLoc loc(manager.getPresumedLoc(location));
    char const* filename(loc.getFilename());
    if (filename) {
        d_file   = filename;
        d_line   = loc.getLine();
        d_column = loc.getColumn();
    }
    else {
        d_file = "<unknown>";
    }
}

// -----------------------------------------------------------------------------

std::string csabase::Location::file() const
{
    return d_file;
}

size_t csabase::Location::line() const
{
    return d_line;
}

size_t csabase::Location::column() const
{
    return d_column;
}

SourceLocation csabase::Location::location() const
{
    return d_location;
}

bool csabase::Location::operator<(Location const& rhs) const
{
    if (d_file < rhs.d_file) {
        return true;
    }
    if (rhs.d_file < d_file) {
        return false;
    }
    if (d_line < rhs.d_line) {
        return true;
    }
    if (rhs.d_line < d_line) {
        return false;
    }
    if (d_column < rhs.d_column) {
        return true;
    }
    if (rhs.d_column < d_column) {
        return false;
    }
    return false;
}

csabase::Location::operator bool() const
{
    return d_location.isValid();
}

// -----------------------------------------------------------------------------

llvm::raw_ostream& csabase::operator<<(llvm::raw_ostream& out,
                                       Location const& loc)
{
    return out << loc.file() << ":" << loc.line() << ":" << loc.column();
}

// -----------------------------------------------------------------------------

std::ostream& csabase::operator<<(std::ostream& out, Location const& loc)
{
    return out << loc.file() << ":" << loc.line() << ":" << loc.column();
}

// -----------------------------------------------------------------------------

bool csabase::operator==(Location const& a, Location const& b)
{
    return a.file()   == b.file()
        && a.line()   == b.line()
        && a.column() == b.column();
}

// -----------------------------------------------------------------------------

bool csabase::operator!=(Location const& a, Location const& b)
{
    return a.file()   != b.file()
        || a.line()   != b.line()
        || a.column() != b.column();
}

// -----------------------------------------------------------------------------

csabase::Range::Range()
{
}

csabase::Range::Range(SourceManager const& manager, SourceRange range)
: d_from(manager, range.getBegin())
, d_to(manager, range.getEnd())
{
}

// -----------------------------------------------------------------------------

const csabase::Location& csabase::Range::from() const
{
    return d_from;
}

const csabase::Location& csabase::Range::to() const
{
    return d_to;
}

bool csabase::Range::operator<(Range const& rhs) const
{
    if (d_from < rhs.d_from) {
        return true;
    }
    if (rhs.d_from < d_from) {
        return false;
    }
    if (d_to < rhs.d_to) {
        return true;
    }
    if (rhs.d_to < d_to) {
        return false;
    }
    return false;
}

csabase::Range::operator bool() const
{
    return d_from && d_to && d_from.file() == d_to.file();
}

// -----------------------------------------------------------------------------

llvm::raw_ostream& csabase::operator<<(llvm::raw_ostream& out,
                                       Range const& loc)
{
    return out << "[" << loc.from() << ", " << loc.to() << "]";
}

// -----------------------------------------------------------------------------

std::ostream& csabase::operator<<(std::ostream& out, Range const& loc)
{
    return out << "[" << loc.from() << ", " << loc.to() << "]";
}

// -----------------------------------------------------------------------------

bool csabase::operator==(Range const& a, Range const& b)
{
    return a.from() == b.from() && a.to() == b.to();
}

// -----------------------------------------------------------------------------

bool csabase::operator!=(Range const& a, Range const& b)
{
    return a.from() != b.from() || a.to() != b.to();
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
