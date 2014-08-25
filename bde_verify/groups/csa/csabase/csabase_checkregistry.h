// csabase_checkregistry.h                                            -*-C++-*-

#ifndef INCLUDED_CSABASE_CHECKREGISTRY
#define INCLUDED_CSABASE_CHECKREGISTRY

#include <utils/function.hpp>
#include <string>

// -----------------------------------------------------------------------------

namespace csabase { class Analyser; }
namespace csabase { class Visitor; }
namespace csabase { class PPObserver; }
namespace csabase
{
class CheckRegistry
    // This class maintains a list of all the registered checks.  Essentially,
    // it is a map of (name, function) pairs where the function does the
    // necessary operations to subscribe to the suitable events on the visitor
    // object it gets passed.
{
  public:
    typedef utils::function<void(Analyser&, Visitor&, PPObserver&)> Subscriber;
    static void add_check(std::string const&, Subscriber);
    static void attach(Analyser&, Visitor&, PPObserver&);
};
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
