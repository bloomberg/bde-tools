// csabase_analyse.cpp                                                -*-C++-*-

#include <csabase_analyse.h>
#include <clang/AST/ASTConsumer.h>
#include <clang/AST/DeclBase.h>
#include <clang/AST/DeclGroup.h>
#include <clang/Basic/Diagnostic.h>
#include <clang/Basic/FileManager.h>
#include <clang/Basic/SourceManager.h>
#include <clang/Frontend/CompilerInstance.h>
#include <clang/Rewrite/Core/Rewriter.h>
#include <csabase_analyser.h>
#include <csabase_debug.h>
#include <csabase_diagnosticfilter.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Path.h>
#include <llvm/Support/raw_ostream.h>
#include <stddef.h>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace clang { class ASTContext; }

// -----------------------------------------------------------------------------

using namespace clang;
using namespace csabase;

// -----------------------------------------------------------------------------

namespace
{

class AnalyseConsumer : public ASTConsumer
{
  public:
    AnalyseConsumer(CompilerInstance&   compiler,
                    std::string const&  source,
                    PluginAction const& plugin);
    void Initialize(ASTContext& context);
    bool HandleTopLevelDecl(DeclGroupRef DG);
    void HandleTranslationUnit(ASTContext&);

  private:
    Analyser analyser_;
    std::string const source_;
};
}

// -----------------------------------------------------------------------------

AnalyseConsumer::AnalyseConsumer(CompilerInstance&   compiler,
                                 std::string const&  source,
                                 PluginAction const& plugin)
: analyser_(compiler,
            plugin.debug(),
            plugin.config(),
            plugin.tool_name(),
            plugin.rewrite_dir())
, source_(source)
{
    analyser_.toplevel(source);

    compiler.getDiagnostics().setClient(new DiagnosticFilter(
        analyser_, plugin.toplevel_only(), compiler.getDiagnosticOpts()));
    compiler.getDiagnostics().getClient()->BeginSourceFile(
        compiler.getLangOpts(),
        compiler.hasPreprocessor() ? &compiler.getPreprocessor() : 0);
}

// -----------------------------------------------------------------------------

void
AnalyseConsumer::Initialize(ASTContext& context)
{
    analyser_.context(&context);
}

// -----------------------------------------------------------------------------

bool
AnalyseConsumer::HandleTopLevelDecl(DeclGroupRef DG)
{
    analyser_.process_decls(DG.begin(), DG.end());
    return true;
}

// -----------------------------------------------------------------------------

void
AnalyseConsumer::HandleTranslationUnit(ASTContext&)
{
    analyser_.process_translation_unit_done();

    std::string rd = analyser_.rewrite_dir();
    if (!rd.empty()) {
        for (Rewriter::buffer_iterator b = analyser_.rewriter().buffer_begin(),
                                       e = analyser_.rewriter().buffer_end();
             b != e;
             b++) {
            if (const FileEntry* fe =
                    analyser_.manager().getFileEntryForID(b->first)) {
                llvm::SmallVector<char, 512> path(rd.begin(), rd.end());
                llvm::sys::path::append(
                    path, llvm::sys::path::filename(fe->getName()));
                std::string rewritten_file =
                    std::string(path.begin(), path.end()) + "-rewritten";
                std::string file_error;
                llvm::raw_fd_ostream rfdo(
                    rewritten_file.c_str(), file_error, llvm::sys::fs::F_None);
                if (file_error.empty()) {
                    b->second.write(rfdo);
                } else {
                    ERRS() << file_error << ": cannot open " << rewritten_file
                           << " for rewriting\n";
                }
            }
        }
    }
}

// -----------------------------------------------------------------------------

PluginAction::PluginAction()
: debug_()
, config_(1, "load .bdeverify")
, tool_name_()
, toplevel_only_(false)
{
}

// -----------------------------------------------------------------------------

ASTConsumer* PluginAction::CreateASTConsumer(CompilerInstance& compiler,
                                             llvm::StringRef source)
{
    return new AnalyseConsumer(compiler, source, *this);
}

// -----------------------------------------------------------------------------

bool PluginAction::ParseArgs(CompilerInstance const& compiler,
                             std::vector<std::string> const& args)
{
    for (size_t i = 0; i < args.size(); ++i) {
        llvm::StringRef arg = args[i];
        if (arg == "debug-on")
        {
            Debug::set_debug(true);
            debug_ = true;
        }
        else if (arg == "debug-off")
        {
            Debug::set_debug(false);
            debug_ = false;
        }
        else if (arg == "toplevel-only-on")
        {
            toplevel_only_ = true;
        }
        else if (arg == "toplevel-only-off")
        {
            toplevel_only_ = false;
        }
        else if (arg.startswith("config=")) {
            config_.push_back("load " + arg.substr(7).str());
        }
        else if (arg.startswith("config-line=")) {
            config_.push_back(arg.substr(12));
        }
        else if (arg.startswith("tool=")) {
            tool_name_ = "[" + arg.substr(5).str() + "] ";
        }
        else if (arg.startswith("rewrite-dir=")) {
            rewrite_dir_ = arg.substr(12).str();
        }
        else
        {
            llvm::errs() << "unknown csabase argument = '" << arg << "'\n";
        }
    }
    return true;
}

bool PluginAction::debug() const
{
    return debug_;
}

const std::vector<std::string>& PluginAction::config() const
{
    return config_;
}

std::string PluginAction::tool_name() const
{
    return tool_name_;
}

bool PluginAction::toplevel_only() const
{
    return toplevel_only_;
}

std::string PluginAction::rewrite_dir() const
{
    return rewrite_dir_;
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
