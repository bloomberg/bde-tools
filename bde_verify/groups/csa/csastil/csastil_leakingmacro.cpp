// csastil_leakingmacro.cpp                                           -*-C++-*-

#include <clang/Basic/IdentifierTable.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Lex/Token.h>
#include <csabase_analyser.h>
#include <csabase_binder.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_filenames.h>
#include <csabase_location.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <llvm/ADT/StringRef.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <map>
#include <stack>
#include <string>
#include <utility>

namespace clang { class MacroDirective; }
namespace csabase { class Visitor; }

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("leaking-macro");

// ----------------------------------------------------------------------------

namespace
{
    struct leaking_macro
    {
        typedef std::map<std::string, SourceLocation> map_type;
        std::stack<map_type> d_macros;
        leaking_macro()
        {
            d_macros.push(map_type());
        }
    };
}

// ----------------------------------------------------------------------------

static void onOpenFile(Analyser* analyser,
                       SourceLocation location,
                       std::string const& current,
                       std::string const& opened)
{
    leaking_macro& context(analyser->attachment<leaking_macro>());
    context.d_macros.push(leaking_macro::map_type());
}

// ----------------------------------------------------------------------------

static void onCloseFile(Analyser* analyser,
                        SourceLocation location,
                        std::string const& current,
                        std::string const& closed)
{
    FileName fn(closed);
    std::string component = llvm::StringRef(fn.component()).upper();

    leaking_macro& context(analyser->attachment<leaking_macro>());
    for (const auto& macro : context.d_macros.top()) {
        Location where(analyser->get_location(macro.second));
        if (   where.file() != "<built-in>"
            && where.file() != "<command line>"
            && macro.first.find("INCLUDED_") != 0
            && (   analyser->is_component_header(macro.second)
                || macro.first.size() < 4)
            && llvm::StringRef(macro.first).upper().find(component) != 0
            )
        {
            analyser->report(macro.second, check_name, "SLM01",
                             "Macro definition '%0' leaks from header",
                             true)
                << macro.first;
        }
    }
    context.d_macros.pop();
}

// ----------------------------------------------------------------------------

static void onMacroDefined(Analyser* analyser,
                           Token const& token,
                           MacroDirective const* info)
{
    leaking_macro& context(analyser->attachment<leaking_macro>());
    std::string source(token.getIdentifierInfo()->getNameStart());
    context.d_macros.top().insert(std::make_pair(source, token.getLocation()));
}

static void onMacroUndefined(Analyser* analyser,
                             Token const& token,
                             MacroDirective const* info)
{
    leaking_macro& context(analyser->attachment<leaking_macro>());
    std::string source(token.getIdentifierInfo()->getNameStart());
    context.d_macros.top().erase(source);
}

// ----------------------------------------------------------------------------

static void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
{
    observer.onOpenFile       += bind(&analyser, &onOpenFile);
    observer.onCloseFile      += bind(&analyser, &onCloseFile);
    observer.onMacroDefined   += bind(&analyser, &onMacroDefined);
    observer.onMacroUndefined += bind(&analyser, &onMacroUndefined);
}

// ----------------------------------------------------------------------------

static RegisterCheck register_observer(check_name, &subscribe);

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
