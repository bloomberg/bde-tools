// csabase_analyse.h                                                  -*-C++-*-

#ifndef INCLUDED_CSABASE_UTILSYSE
#define INCLUDED_CSABASE_UTILSYSE

#include <clang/AST/ASTConsumer.h>
#include <clang/Frontend/FrontendAction.h>
#include <llvm/ADT/StringRef.h>
#include <string>
#include <vector>

namespace clang { class CompilerInstance; }

namespace csabase
{
class PluginAction : public clang::PluginASTAction
{
  public:
    PluginAction();

    bool debug() const;
    const std::vector<std::string>& config() const;
    std::string tool_name() const;
    bool toplevel_only() const;
    std::string rewrite_dir() const;

  protected:
    clang::ASTConsumer* CreateASTConsumer(clang::CompilerInstance& compiler,
                                          llvm::StringRef source);

    bool ParseArgs(clang::CompilerInstance const& compiler,
                   std::vector<std::string> const& args);

  private:
    bool debug_;
    std::vector<std::string> config_;
    std::string tool_name_;
    bool toplevel_only_;
    std::string rewrite_dir_;
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
