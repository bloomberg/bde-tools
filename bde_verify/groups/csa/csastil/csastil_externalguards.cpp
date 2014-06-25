// csastil_externalguards.cpp                                         -*-C++-*-

#include <clang/Basic/IdentifierTable.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Lex/Token.h>
#include <csabase_analyser.h>
#include <csabase_binder.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_filenames.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/Support/Regex.h>
#include <llvm/Support/raw_ostream.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <stack>
#include <string>
#include <utility>

namespace csabase { class Visitor; }

using namespace clang;
using namespace csabase;

// ----------------------------------------------------------------------------

static std::string const check_name("external-guards");

// ----------------------------------------------------------------------------

namespace
{
    struct ExternalGuards
    {
        typedef std::pair<std::string, SourceLocation> condition_type;
        std::stack<condition_type> d_conditions;
    };
}

// ----------------------------------------------------------------------------

static void
onIfdef(Analyser* analyser, SourceLocation where, Token const& token)
{
    ExternalGuards& context(analyser->attachment<ExternalGuards>());
    // This condition is never part of an include guard.
    context.d_conditions.push(std::make_pair(std::string(), where));
}

// ----------------------------------------------------------------------------

static void
onIfndef(Analyser* analyser, SourceLocation where, Token const& token)
{
    llvm::StringRef guard = token.getIdentifierInfo()->getName();
    if (!guard.startswith("INCLUDE")) {
        guard = llvm::StringRef();
    }
    analyser->attachment<ExternalGuards>().d_conditions.push(
        std::make_pair(guard.str(), where));
}

// ----------------------------------------------------------------------------

static llvm::Regex ndef(
    "^ *! *defined *[(]? *(INCLUDE[_[:alnum:]]*) *[)]? *$");

static void onIf(Analyser* analyser, SourceLocation where, SourceRange source)
{
    llvm::SmallVector<llvm::StringRef, 7> matches;
    llvm::StringRef guard;
    if (ndef.match(analyser->get_source(source), &matches)) {
        guard = matches[1];
    }
    analyser->attachment<ExternalGuards>().d_conditions.push(
        std::make_pair(guard, where));
}

// ----------------------------------------------------------------------------

static llvm::Regex next_include_before_if(
    "(^ *# *if)|"                     // 1
    "(^ *# *include *\"([^\"]*)\")|"  // 2, 3
    "(^ *# *include *<([^>]*)>)",     // 4, 5
    llvm::Regex::Newline
);

static std::string getInclude(llvm::StringRef source)
{
    llvm::SmallVector<llvm::StringRef, 7> matches;
    if (next_include_before_if.match(source, &matches)) {
        if (matches[3].size()) {
            return matches[3];
        }
        if (matches[5].size()) {
            return matches[5];
        }
    }
    return std::string();
}

static void onEndif(Analyser* analyser, SourceLocation end, SourceLocation)
{
    ExternalGuards& context(analyser->attachment<ExternalGuards>());
    if (!context.d_conditions.empty()) {
        std::string guard = context.d_conditions.top().first;
        SourceLocation where = context.d_conditions.top().second;
        std::string component_guard =
            "INCLUDED_" + llvm::StringRef(analyser->component()).upper();
        if (analyser->is_component_header(end)
            && !guard.empty()
            && guard != component_guard
            ) {
            std::string include =
                getInclude(analyser->get_source(SourceRange(where, end)));
            std::string include_guard =
                "INCLUDED_" + FileName(include).component().upper();
            if (include.empty()) {
                analyser->report(where, check_name, "SEG01",
                                 "Include guard '%0' without include file")
                    << guard;
            }
            else if (   include_guard != guard
                     && (   include.find('_') != include.npos
                         || include_guard + "_H" != guard)
                     ) {
                analyser->report(where, check_name, "SEG02",
                                 "Include guard '%0' mismatch for included "
                                 "file '%1' - use '%2'")
                    << guard
                    << include
                    << (include.find('_') == include.npos ?
                            include_guard + "_H" :
                            include_guard);
            }
        }
        context.d_conditions.pop();
    }
    else {
        // This "can't happen" unless Clang's PPObserver interface changes so
        // that our functions are no longer virtual overrides.  This happens
        // distressingly often.
        llvm::errs() << "Mismatched conditionals?\n";
    }
}

// ----------------------------------------------------------------------------

static void onInclude(Analyser* analyser,
                      SourceLocation where,
                      bool,
                      std::string const& file)
{
    ExternalGuards& context(analyser->attachment<ExternalGuards>());
    if (analyser->is_component_header(where)
        && (context.d_conditions.empty()
            || context.d_conditions.top().first.empty()
            || context.d_conditions.top().first
                == "INCLUDED_" + llvm::StringRef(analyser->component()).upper()
            )
        )
    {
        analyser->report(where, check_name, "SEG03",
                         "Include of '%0' without external include guard "
                         "'%1'")
            << file
            << "INCLUDED_" + FileName(file).component().upper();
    }
}

// ----------------------------------------------------------------------------

static void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
{
    observer.onInclude  += bind(&analyser, &onInclude);
    observer.onIfdef    += bind(&analyser, &onIfdef);
    observer.onIfndef   += bind(&analyser, &onIfndef);
    observer.onIf       += bind(&analyser, &onIf);
    observer.onEndif    += bind(&analyser, &onEndif);
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
