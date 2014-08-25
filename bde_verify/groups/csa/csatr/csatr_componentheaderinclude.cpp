// csatr_componentheaderinclude.cpp                                   -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_binder.h>
#include <csabase_location.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <llvm/Support/Casting.h>
#include <stddef.h>
#include <utils/array.hpp>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <algorithm>
#include <limits>
#include <string>

namespace clang { class Decl; }
namespace csabase { class Visitor; }

using namespace clang;
using namespace csabase;

// ----------------------------------------------------------------------------

static std::string const check_name("component-header");

// ----------------------------------------------------------------------------

namespace
{
    struct data
    {
        data()
        : check_(true)
        , header_seen_(false)
        , line_(std::numeric_limits<size_t>::max())
        {
        }
        bool   check_;
        bool   header_seen_;
        size_t line_;
    };
}

// ----------------------------------------------------------------------------

static std::string const builtin("<built-in>");
static std::string const command_line("<command line>");
static std::string const id_names[] = { "RCSId" };

// ----------------------------------------------------------------------------

static void close_file(Analyser& analyser,
                       SourceLocation where,
                       std::string const&,
                       std::string const& name)
{
    if (analyser.is_component_header(name))
    {
        analyser.attachment<data>().line_ =
            analyser.get_location(where).line();
    }
}

// ----------------------------------------------------------------------------

static void include_file(Analyser& analyser,
                         SourceLocation where,
                         bool,
                         std::string const& name)
{
    data& status(analyser.attachment<data>());
    if (status.check_)
    {
        if (analyser.is_component_header(name) ||
            analyser.is_component_header(analyser.toplevel()))
        {
            status.header_seen_ = true;
        }
        else if (!status.header_seen_
                 && analyser.toplevel() != name
                 && builtin != name
                 && command_line != name
                 && "bdes_ident.h" != name
                 && !analyser.is_main())
        {
            analyser.report(where, check_name, "TR09",
                            "Include files precede component header",
                            true);
            status.check_ = false;
        }
    }
}

// ----------------------------------------------------------------------------

static void declaration(Analyser& analyser, Decl const* decl)
{
    data& status(analyser.attachment<data>());
    if (status.check_)
    {
        if (!status.header_seen_ ||
            analyser.is_component_header(analyser.toplevel()))
        {
            status.header_seen_ = true;
            status.line_ = 0;
        }

        Location loc(analyser.get_location(decl));
        if ((analyser.toplevel() != loc.file() && status.header_seen_)
            || (analyser.toplevel() == loc.file()
                && status.line_ < loc.line()))
        {
            status.check_ = false;
        }
        else if (((analyser.toplevel() != loc.file() && !status.header_seen_)
                  || loc.line() < status.line_)
                 && builtin != loc.file() && command_line != loc.file()
                 && (llvm::dyn_cast<NamedDecl>(decl) == 0
                     || utils::end(id_names)
                          == std::find(utils::begin(id_names),
                                       utils::end(id_names),
                                       llvm::dyn_cast<NamedDecl>(decl)
                                                          ->getNameAsString()))
                 && !analyser.is_main())
        {
            analyser.report(decl, check_name, "TR09",
                            "Declarations precede component header",
                            true);
            status.check_ = false;
        }
    }
}

// -----------------------------------------------------------------------------

static void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
{
    observer.onInclude   += bind<Analyser&>(analyser, include_file);
    observer.onCloseFile += bind<Analyser&>(analyser, close_file);
}

// -----------------------------------------------------------------------------

static RegisterCheck register_observer(check_name, &subscribe);
static RegisterCheck register_check(check_name, &declaration);

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
