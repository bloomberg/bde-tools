// csamisc_includeguard.cpp                                           -*-C++-*-

#include "framework/analyser.hpp"
#include "framework/pp_observer.hpp"
#include "framework/register_check.hpp"
#include "framework/location.hpp"
#include "utils/array.hpp"
#include <csabase_filenames.h>
#include "clang/Basic/SourceLocation.h"
#include <algorithm>
#include <string>
#include <ctype.h>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("include-guard");

// -----------------------------------------------------------------------------

namespace
{
bool is_space(unsigned char c)
{
    return isspace(c);
}
char to_upper(unsigned char c)
{
    return toupper(c);
}
}

// -----------------------------------------------------------------------------

namespace
{
std::string
get_string(Analyser* analyser, SourceLocation begin, SourceLocation end)
{
    return std::string(
        FullSourceLoc(begin, analyser->manager()).getCharacterData(),
        FullSourceLoc(end, analyser->manager()).getCharacterData());
}
}

// -----------------------------------------------------------------------------

namespace
{
static std::string const suffixes[] = { ".h",   ".H",   ".hh",
                                        ".h++", ".hpp", ".hxx" };

void inspect_guard_name(Analyser* analyser,
                        SourceLocation begin,
                        std::string const& name)
{
    FileName fn(analyser->get_location(begin).file());
    if (bde_verify::end(suffixes) == std::find(bde_verify::begin(suffixes),
                                               bde_verify::end(suffixes),
                                               fn.extension().str())) {
        analyser->report(
            begin,
            check_name,
            "HS01",
            "Unknown header file suffix: '" + fn.extension().str() + "'");
    } else {
        std::string file = "INCLUDED_" + fn.prefix().str();
        if (2 <= file.size() && ".t" == file.substr(file.size() - 2)) {
            file[file.size() - 2] = '_';
        }
        std::transform(file.begin(), file.end(), file.begin(), to_upper);
        if (file != name) {
            analyser->report(begin,
                             check_name,
                             "IG01",
                             "Expected include guard '" + name + "'");
        }
    }
}
}

// -----------------------------------------------------------------------------

namespace
{
std::string const not_defined("!defined(");
void on_if(Analyser* analyser, SourceRange range)
{
    std::string expr(get_string(analyser, range.getBegin(), range.getEnd()));
    expr.erase(std::remove_if(expr.begin(), expr.end(), is_space), expr.end());
    if (0 == expr.find(not_defined) && *(expr.end() - 1) == ')') {
        inspect_guard_name(analyser,
                           range.getBegin(),
                           expr.substr(not_defined.size(),
                                       expr.size() - not_defined.size() - 1));
    }
}
}

// -----------------------------------------------------------------------------

namespace
{
void on_ifndef(Analyser* analyser, Token token)
{
    //-dk:TODO remove llvm::errs() << "onIfndef\n";
    inspect_guard_name(
        analyser,
        token.getLocation(),
        get_string(analyser, token.getLocation(), token.getLastLoc()));
}
}

// -----------------------------------------------------------------------------

static void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
{
    observer.onIf      += std::bind1st(std::ptr_fun(on_if), &analyser);
    observer.onIfndef  += std::bind1st(std::ptr_fun(on_ifndef), &analyser);
}

// -----------------------------------------------------------------------------

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
