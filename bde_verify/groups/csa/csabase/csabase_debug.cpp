// csabase_debug.cpp                                                  -*-C++-*-

#include <csabase_debug.h>
#include <llvm/Support/raw_ostream.h>

// -----------------------------------------------------------------------------

namespace
{
    unsigned int level(0);
    bool         do_debug(false);
}

// -----------------------------------------------------------------------------

namespace
{
    static llvm::raw_ostream& start(unsigned int depth)
    {
        llvm::raw_ostream& out(llvm::errs());
        for (unsigned int i(0); i != depth; ++i)
        {
            out << " ";
        }
        return out;
    }
}

// -----------------------------------------------------------------------------

void csabase::Debug::set_debug(bool value)
{
    do_debug = value;
}

bool csabase::Debug::get_debug()
{
    return do_debug;
}

// -----------------------------------------------------------------------------

csabase::Debug::Debug(char const* message, bool nest)
: message_(message)
, nest_(nest)
{
    if (do_debug)
    {
        start(level) << (nest_ ? "\\ " : "| ") << "'" << message_ << "'\n";
        level += nest;
    }
}

csabase::Debug::~Debug()
{
    if (do_debug && nest_)
    {
        start(level -= nest_) << (nest_ ? "/ " : "| ") << message_ << "\n";
    }
}

// -----------------------------------------------------------------------------

namespace
{
    llvm::raw_null_ostream dummy_stream;
}

llvm::raw_ostream& csabase::Debug::indent() const
{
    return do_debug ? start(level) << "| ": dummy_stream;
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
