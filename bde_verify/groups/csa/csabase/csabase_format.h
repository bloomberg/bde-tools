// csabase_format.h                                                   -*-C++-*-

#ifndef INCLUDED_CSABASE_FORMAT
#define INCLUDED_CSABASE_FORMAT

namespace clang { class DiagnosticBuilder; }
namespace llvm { class raw_ostream; }

// ----------------------------------------------------------------------------

namespace csabase
{
template <typename T>
class Formatter
{
public:
    Formatter(T const& value);
    void print(llvm::raw_ostream&) const;
    void print(clang::DiagnosticBuilder&) const;

private:
    T const& value_;
};

template <typename T>
inline
Formatter<T>::Formatter(T const& value)
: value_(value)
{
}

// -----------------------------------------------------------------------------

template <typename T>
inline
Formatter<T> format(T const& value)
{
    return Formatter<T>(value);
}

// -----------------------------------------------------------------------------

template <typename T>
inline
llvm::raw_ostream& operator<<(llvm::raw_ostream& out,
                              Formatter<T> const& value)
{
    value.print(out);
    return out;
}

template <typename T>
inline
clang::DiagnosticBuilder& operator<<(clang::DiagnosticBuilder& builder,
                                     Formatter<T> const& value)
{
    value.print(builder);
    return builder;
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
