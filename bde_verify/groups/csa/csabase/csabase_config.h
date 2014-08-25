// csabase_config.h                                                   -*-C++-*-

#ifndef INCLUDED_CSABASE_CONFIG
#define INCLUDED_CSABASE_CONFIG

#include <clang/Basic/SourceLocation.h>
#include <iosfwd>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace clang { class SourceManager; }

// -----------------------------------------------------------------------------

namespace csabase { class Analyser; }
namespace csabase
{
class Config
{
public:
    enum Status
    {
        off,
        on
    };

    Config(std::vector<std::string> const& config,
           clang::SourceManager& manager);
        // Create a 'Config' object initialized with the set of specified
        // 'config' lines, and holding the specified 'manager'.

    void load(std::string const& file);
        // Read a set of configuration lines from the specified 'file'.

    void process(std::string const& line);
        // Append the specifed 'line' to the configuration.

    std::string const& toplevel_namespace() const;

    std::map<std::string, Status> const& checks() const;

    void set_value(const std::string& key, const std::string& value);

    std::string const&
    value(const std::string& key,
          clang::SourceLocation where = clang::SourceLocation()) const;

    bool all() const;

    void bv_stack_level(std::vector<clang::SourceLocation> *stack,
                        clang::SourceLocation where) const;
        // Populate the specified 'stack' with the pragma bdeverify stack
        // locations for the specified location 'where'.

    bool suppressed(const std::string& tag, clang::SourceLocation where) const;
        // Return 'true' iff a diagnostic with the specified 'tag' should be
        // suppressed at the specified location 'where'.

    void push_suppress(clang::SourceLocation where);
        // Push a level onto the local diagnostics suppressions stack for the
        // specified location 'where'.

    void pop_suppress(clang::SourceLocation where);
        // Pop a level from the local diagnostics suppressions stack for the
        // specified location 'where', if the stack is not empty..

    void suppress(const std::string& tag,
                  clang::SourceLocation where,
                  bool on,
                  std::set<std::string> in_progress = std::set<std::string>());
        // Mark the specified 'tag' as suppressed or not at the current stack
        // level and the specified location 'where', depending on the state of
        // the 'on' flag.  If 'tag' is the name of a group, recursively process
        // the members of the group unles 'tag' is present in the optionally
        // specified 'in_progress' set.

    void set_bv_value(clang::SourceLocation where,
                      const std::string& variable,
                      const std::string& value);
        // Record, for the specified location 'where', the appearance of a
        // specified '#pragma bdeverify set variable value'.

    void check_bv_stack(Analyser& analyser) const;
        // Verify that the csabase pragmas form a proper stack.

private:
    std::string                                      d_toplevel_namespace;
    std::vector<std::string>                         d_loadpath;
    std::map<std::string, Status>                    d_checks;
    std::map<std::string, std::vector<std::string> > d_groups;
    std::map<std::string, std::string>               d_values;
    std::set<std::pair<std::string, std::string> >   d_suppressions;

    struct BVData
    {
        clang::SourceLocation where;
        char type;
        std::string s1;
        std::string s2;

        BVData(clang::SourceLocation where,
               char type,
               const std::string& s1 = std::string(),
               const std::string& s2 = std::string())
            : where(where), type(type), s1(s1), s2(s2)
        {
        }
    };

    std::map<std::string, std::vector<BVData> >      d_local_bv_pragmas;
    Status                                           d_all;
    clang::SourceManager&                            d_manager;
};

std::istream& operator>>(std::istream&, Config::Status&);
std::ostream& operator<<(std::ostream&, Config::Status);
}

// -----------------------------------------------------------------------------

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
