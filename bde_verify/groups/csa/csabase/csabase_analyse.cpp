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
#include <csabase_filenames.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Path.h>
#include <llvm/Support/raw_ostream.h>
#include <limits.h>
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 600  // For 'realpath'
#endif
#include <stdlib.h>
#include <stddef.h>
#include <fstream>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace clang { class ASTContext; }

// -----------------------------------------------------------------------------

using namespace clang;
using namespace clang::tooling;
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
    ~AnalyseConsumer();
    void Initialize(ASTContext& context);
    bool HandleTopLevelDecl(DeclGroupRef DG);
    llvm::StringRef Canon(llvm::StringRef path);
    void ReadReplacements(std::string file);
    void HandleTranslationUnit(ASTContext&);

  private:
    Analyser analyser_;
    std::string const source_;
    std::map<std::string, std::string> canon_;
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
            plugin.rewrite_dir(),
            plugin.rewrite_file())
, source_(source)
{
    analyser_.toplevel(source);

    compiler.getDiagnostics().setClient(new DiagnosticFilter(
        analyser_, plugin.diagnose(), compiler.getDiagnosticOpts()));
    compiler.getDiagnostics().getClient()->BeginSourceFile(
        compiler.getLangOpts(),
        compiler.hasPreprocessor() ? &compiler.getPreprocessor() : 0);
}

// -----------------------------------------------------------------------------

AnalyseConsumer::~AnalyseConsumer()
{
    analyser_.compiler().getDiagnostics().getClient()->EndSourceFile();
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

llvm::StringRef
AnalyseConsumer::Canon(llvm::StringRef path)
{
    std::string ps = path.str();
    auto i = canon_.find(ps);
    if (i != canon_.end()) {
        return i->second;
    }
    char buf[PATH_MAX];
    const char *pc = realpath(ps.c_str(), buf);
    if (!pc) {
        pc = ps.c_str();
    }
    return canon_[path] = std::string(pc);
}

void
AnalyseConsumer::ReadReplacements(std::string file)
{
    if (!file.empty()) {
        std::ifstream f(file);
        if (!f) {
            llvm::errs() << analyser_.toplevel()
                         << ":1:1: error: cannot open " << file
                         << " for reading\n";
        }
        else {
            int length;
            std::string mod_file;
            int rep_offset;
            int rep_length;
            std::string data;
            while (f >> length) {
                mod_file.resize(length);
                f.ignore(1).read(&mod_file[0], mod_file.size()).ignore(1);
                f >> rep_offset >> rep_length >> length;
                data.resize(length);
                f.ignore(1).read(&data[0], data.size()).ignore(1);
                mod_file = Canon(mod_file);
                analyser_.ReplaceText(mod_file, rep_offset, rep_length, data);
            }
        }
    }
}

struct CompareReplacements
{
    bool operator()(const Replacement &a, const Replacement &b)
    {
        if (a.getFilePath() < b.getFilePath()) {
            return true;
        }
        if (b.getFilePath() < a.getFilePath()) {
            return false;
        }
        if (a.getOffset() > b.getOffset()) {
            return true;
        }
        if (b.getOffset() > a.getOffset()) {
            return false;
        }
        if (a.getLength() < b.getLength()) {
            return true;
        }
        if (b.getLength() < a.getLength()) {
            return false;
        }
        return b.getReplacementText() < a.getReplacementText();
    }
};

void
AnalyseConsumer::HandleTranslationUnit(ASTContext&)
{
    analyser_.process_translation_unit_done();

    std::string rf = analyser_.rewrite_file();
    if (!rf.empty()) {
        int fd;
        std::error_code file_error = llvm::sys::fs::openFileForWrite(
            rf, fd, llvm::sys::fs::F_Append);
        if (file_error) {
            llvm::errs() << analyser_.toplevel()
                         << ":1:1: error: " << file_error.message()
                         << ": cannot open " << rf
                         << " for writing\n";
        }
        else {
            llvm::raw_fd_ostream rfdo(fd, true);
            rfdo.SetUnbuffered();
            rfdo.SetUseAtomicWrites(true);
            for (const auto &r : analyser_.replacements()) {
                std::string buf;
                llvm::raw_string_ostream os(buf);
                llvm::StringRef c = Canon(r.getFilePath());
                os << c.size() << " "
                   << c << " "
                   << r.getOffset() << " "
                   << r.getLength() << " "
                   << r.getReplacementText().size() << " "
                   << r.getReplacementText() << "\n";
                rfdo << os.str();
            }
            rfdo.close();
            if (rfdo.has_error()) {
                rfdo.clear_error();
                llvm::errs() << analyser_.toplevel() << ":1:1: error: "
                             << "IO error closing " << rf << "\n";
            }
        }
    }

    std::string rd = analyser_.rewrite_dir();
    if (!rd.empty()) {
        if (!rf.empty()) {
            ReadReplacements(rf);
        }
        Rewriter& rw = analyser_.rewriter();
        SourceManager&m = analyser_.manager();
        std::set<Replacement, CompareReplacements> sr(
            analyser_.replacements().begin(), analyser_.replacements().end());
        for (const auto &r : sr) {
            r.apply(rw);
        }
        Rewriter::buffer_iterator b = rw.buffer_begin();
        Rewriter::buffer_iterator e = rw.buffer_end();
        for (; b != e; b++) {
            const FileEntry *fe = m.getFileEntryForID(b->first);
            if (!fe) {
                continue;
            }
            std::string rewritten_file =
                analyser_.get_rewrite_file(fe->getName());
            const int MAX_TRIES = 10;
            int tries;
            llvm::SmallVector<char, 256> path;
            for (tries = 0; ++tries <= MAX_TRIES;
                 llvm::sys::fs::remove(path.data())) {
                int fd;
                std::error_code file_error =
                    llvm::sys::fs::createUniqueFile(
                        rewritten_file + "-%%%%%%%%", fd, path);
                if (file_error) {
                    llvm::errs() << analyser_.toplevel()
                                 << ":1:1: error: " << file_error.message()
                                 << ": cannot open " << path.data()
                                 << " for writing -- attempt " << tries
                                 << "\n";
                    continue;
                }
                llvm::raw_fd_ostream rfdo(fd, true);
                b->second.write(rfdo);
                rfdo.close();
                if (rfdo.has_error()) {
                    rfdo.clear_error();
                    llvm::errs() << analyser_.toplevel() << ":1:1: error: "
                                 << "IO error closing " << path.data()
                                 << " -- attempt " << tries << "\n";
                    continue;
                }
                file_error =
                    llvm::sys::fs::rename(path.data(), rewritten_file);
                if (file_error) {
                    llvm::errs() << analyser_.toplevel() << ":1:1: error: "
                                 << "cannot rename " << path.data()
                                 << " to " << rewritten_file
                                 << " -- attempt " << tries << "\n";
                    continue;
                }
                break;
            }
            if (tries == MAX_TRIES) {
                llvm::errs() << analyser_.toplevel() << ":1:1: error: "
                             << "utterly failed to produce "
                             << rewritten_file << "\n";
            }
            else {
                llvm::errs() << analyser_.toplevel() << ":1:1: note: "
                << "wrote " << rewritten_file << "\n";
            }
        }
    }
}

// -----------------------------------------------------------------------------

PluginAction::PluginAction()
: debug_()
, config_(1, "load .bdeverify")
, tool_name_()
, diagnose_("component")
{
}

// -----------------------------------------------------------------------------

std::unique_ptr<ASTConsumer>
PluginAction::CreateASTConsumer(CompilerInstance& compiler,
                                llvm::StringRef source)
{
    return std::unique_ptr<ASTConsumer>(
        new AnalyseConsumer(compiler, source, *this));
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
            diagnose_ = "main";
        }
        else if (arg.startswith("diagnose=")) {
            diagnose_ = arg.substr(9).str();
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
        else if (arg.startswith("rewrite-file=")) {
            rewrite_file_ = arg.substr(13).str();
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

std::string PluginAction::diagnose() const
{
    return diagnose_;
}

std::string PluginAction::rewrite_dir() const
{
    return rewrite_dir_;
}

std::string PluginAction::rewrite_file() const
{
    return rewrite_file_;
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
