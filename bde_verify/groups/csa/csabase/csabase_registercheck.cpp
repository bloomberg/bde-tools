// csabase_registercheck.cpp                                          -*-C++-*-

#include <csabase_registercheck.h>
#include <csabase_binder.h>
#include <csabase_checkregistry.h>
#include <csabase_visitor.h>

namespace clang { class Decl; }
namespace clang { class Expr; }
namespace clang { class Stmt; }
namespace utils { template <typename Signature> class event; }

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

namespace
{
template <typename T>
struct add_to_event
{
    add_to_event(utils::event<void(T const*)> Visitor::*member,
                 void (*check)(Analyser&, T const*));
    void operator()(Analyser& a, Visitor& v, PPObserver&);

    utils::event<void(T const*)> Visitor::*member_;
    void (*check_)(Analyser&, T const*);
};

template <typename T>
add_to_event<T>::add_to_event(utils::event<void(T const*)> Visitor::*member,
                              void (*check)(Analyser&, T const*))
: member_(member), check_(check)
{
}

template <typename T>
void add_to_event<T>::operator()(Analyser& a, Visitor& v, PPObserver&)
{
    v.*member_ += Binder<Analyser&, void(*)(Analyser&, T const *)>(a, check_);
}
}

// -----------------------------------------------------------------------------

namespace csabase
{
#define REGISTER(D)                                                  \
    template <>                                                      \
    RegisterCheck::RegisterCheck(                                    \
        std::string const& name, void (*check)(Analyser&, D const*)) \
    {                                                                \
        CheckRegistry::add_check(                                    \
            name, add_to_event<D>(&Visitor::on##D, check));          \
    }

#define ABSTRACT_DECL(ARG) ARG
#define DECL(CLASS, BASE) REGISTER(CLASS##Decl)
DECL(, )
#include "clang/AST/DeclNodes.inc"

#define ABSTRACT_STMT(STMT)
#define STMT(CLASS, PARENT) REGISTER(CLASS)
STMT(Stmt, )
#include "clang/AST/StmtNodes.inc"
REGISTER(Expr)

RegisterCheck::RegisterCheck(
    std::string const & name, CheckRegistry::Subscriber subscriber)
{
    CheckRegistry::add_check(name, subscriber);
}

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
