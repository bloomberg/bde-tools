// csabase_debug.h                                                    -*-C++-*-

#ifndef INCLUDED_CSABASE_DEBUG
#define INCLUDED_CSABASE_DEBUG

#include <llvm/Support/raw_ostream.h>

// -----------------------------------------------------------------------------

namespace csabase
{
class Debug
{
public:
    static void set_debug(bool);
    static bool get_debug();

    Debug(char const*, bool nest = true);
    ~Debug();
    template <typename T> llvm::raw_ostream& operator<< (T const& value) const;

private:
    Debug(Debug const&);
    void operator= (Debug const&);
    llvm::raw_ostream& indent() const;

    char const*  message_;
    unsigned int nest_;
};

// -----------------------------------------------------------------------------

template <typename T>
inline
llvm::raw_ostream& Debug::operator<<(T const& value) const
{
    return indent() << value;
}
}


// -----------------------------------------------------------------------------

#define ERRS() (llvm::errs() << __FUNCTION__ << " " << __LINE__ << " ")
#define ERNL() (llvm::errs() << "\n")
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
