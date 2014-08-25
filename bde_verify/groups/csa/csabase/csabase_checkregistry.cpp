// csabase_checkregistry.cpp                                          -*-C++-*-

#include <csabase_checkregistry.h>
#include <csabase_analyser.h>
#include <csabase_config.h>
#include <llvm/Support/raw_ostream.h>
#include <map>
#include <utility>

using namespace csabase;

// -----------------------------------------------------------------------------

namespace
{
typedef std::multimap<std::string, CheckRegistry::Subscriber> map_type;

map_type& checks()
{
    static map_type rc;
    return rc;
}
}

// -----------------------------------------------------------------------------

void
csabase::CheckRegistry::add_check(std::string const& name,
                                  CheckRegistry::Subscriber check)
{
    checks().insert(std::make_pair(name, check));
}

// -----------------------------------------------------------------------------

void
csabase::CheckRegistry::attach(Analyser& analyser,
                               Visitor& visitor,
                               PPObserver& observer)
{
    typedef map_type::const_iterator const_iterator;
    typedef std::map<std::string, Config::Status> checks_type;
    checks_type const& config(analyser.config()->checks());
    for (const auto &cfg : config) {
        if (checks().find(cfg.first) == checks().end()) {
            llvm::errs() << "unknown check '" << cfg.first << "'; "
                         << "existing checks:\n";
            for (const_iterator cit(checks().begin()), cend(checks().end());
                 cit != cend; cit = checks().equal_range(cit->first).second) {
                llvm::errs() << "  check " << cit->first << " on\n";
            }
            break;
        }
    }

    for (const auto& check : checks()) {
        checks_type::const_iterator cit(config.find(check.first));
        if ((config.end() != cit && cit->second == Config::on) ||
            (config.end() == cit && analyser.config()->all())) {
            check.second(analyser, visitor, observer);
        }
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
