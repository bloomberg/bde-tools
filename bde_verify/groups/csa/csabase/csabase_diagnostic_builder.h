// csabase_diagnostic_builder.h                                       -*-C++-*-

#ifndef FRAMEWORK_DIAGNOSTIC_BUILDER_HPP
#define FRAMEWORK_DIAGNOSTIC_BUILDER_HPP

#include <clang/Basic/Diagnostic.h>

// -----------------------------------------------------------------------------

namespace csabase
{
class diagnostic_builder
{
  public:
    diagnostic_builder();
    explicit diagnostic_builder(clang::DiagnosticBuilder other);
    diagnostic_builder& operator<<(long long argument);
    diagnostic_builder& operator<<(long argument);
    template <typename T>
    diagnostic_builder& operator<<(T const& argument);

  private:
    bool empty_;
    clang::DiagnosticBuilder builder_;
};

inline
diagnostic_builder::diagnostic_builder()
: empty_(true), builder_(clang::DiagnosticBuilder::getEmpty())
{
}

inline
diagnostic_builder::diagnostic_builder(clang::DiagnosticBuilder other)
: empty_(false), builder_(other)
{
}

inline
diagnostic_builder& diagnostic_builder::operator<<(long long argument)
{
    return *this << static_cast<int>(argument);
}

inline
diagnostic_builder& diagnostic_builder::operator<<(long argument)
{
    return *this << static_cast<int>(argument);
}

template <typename T>
inline
diagnostic_builder& diagnostic_builder::operator<<(T const& argument)
{
    if (!empty_) {
        builder_ << argument;
    }
    return *this;
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
