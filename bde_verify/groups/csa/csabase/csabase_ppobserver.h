// csabase_ppobserver.h                                               -*-C++-*-

#ifndef INCLUDED_CSABASE_PPOSERVER
#define INCLUDED_CSABASE_PPOSERVER

#include <clang/Basic/DiagnosticIDs.h>  // for Mapping
#include <clang/Basic/SourceLocation.h>  // for SourceLocation (ptr only), etc
#include <clang/Basic/SourceManager.h>  // for CharacteristicKind, etc
#include <clang/Lex/ModuleLoader.h>     // for ModuleIdPath
#include <clang/Lex/PPCallbacks.h>      // for PPCallbacks, etc
#include <clang/Lex/Pragma.h>           // for PragmaIntroducerKind
#include <llvm/ADT/ArrayRef.h>          // for ArrayRef
#include <llvm/ADT/StringRef.h>         // for StringRef
#include <stack>                        // for stack
#include <string>                       // for string
#include <utils/event.hpp>              // for event

namespace clang { class CommentHandler; }
namespace clang { class FileEntry; }
namespace clang { class IdentifierInfo; }
namespace clang { class MacroArgs; }
namespace clang { class MacroDirective; }
namespace clang { class Module; }
namespace clang { class Token; }
namespace csabase { class Config; }
namespace llvm { template <typename T> class SmallVectorImpl; }

// -----------------------------------------------------------------------------

namespace csabase
{
class PPObserver : public clang::PPCallbacks
{
public:
    PPObserver(clang::SourceManager const*, Config*);
    ~PPObserver();
    void detach();
    clang::CommentHandler* get_comment_handler();

    utils::event<void(clang::SourceLocation, bool, std::string const&)>               onInclude;
    utils::event<
        void(clang::SourceLocation, std::string const &, std::string const &)>
    onOpenFile;
    utils::event<
        void(clang::SourceLocation, std::string const &, std::string const &)>
    onCloseFile;
    utils::event<void(std::string const&, std::string const&)>                        onSkipFile;
    utils::event<void(std::string const&)>                                            onFileNotFound;
    utils::event<void(std::string const &,
                      clang::PPCallbacks::FileChangeReason)> onOtherFile;
    utils::event<void(clang::SourceLocation, std::string const&)>                     onIdent;
    utils::event<void(clang::SourceLocation, std::string const&)>                     onPragma;
    utils::event<void(clang::Token const &,
                      clang::MacroDirective const *,
                      clang::SourceRange,
                      clang::MacroArgs const*)> onMacroExpands;
    utils::event<void(clang::Token const&, clang::MacroDirective const*)>                  onMacroDefined;
    utils::event<void(clang::Token const&, clang::MacroDirective const*)>                  onMacroUndefined;
    utils::event<void(clang::SourceLocation, clang::SourceRange)>                     onIf;
    utils::event<void(clang::SourceLocation, clang::SourceRange)>                     onElif;
    utils::event<void(clang::SourceLocation, clang::Token const&)>                    onIfdef;
    utils::event<void(clang::SourceLocation, clang::Token const&)>                    onIfndef;
    utils::event<void(clang::SourceLocation, clang::SourceLocation)>                  onElse;
    utils::event<void(clang::SourceLocation, clang::SourceLocation)>                  onEndif;
    utils::event<void(clang::SourceRange)>                                            onComment;
    utils::event<void()>                                                              onContext;

    void FileChanged(
                  clang::SourceLocation             Loc,
                  FileChangeReason                  Reason,
                  clang::SrcMgr::CharacteristicKind FileType,
                  clang::FileID                     PrevFID = clang::FileID())
    override;

    void FileSkipped(const clang::FileEntry            &ParentFile,
                     const clang::Token                &FilenameTok,
                     clang::SrcMgr::CharacteristicKind  FileType)
    override;

    bool FileNotFound(llvm::StringRef              FileName,
                      llvm::SmallVectorImpl<char> &RecoveryPath)
    override;

    void InclusionDirective(clang::SourceLocation   HashLoc,
                            const clang::Token&     IncludeTok,
                            llvm::StringRef         FileName,
                            bool                    IsAngled,
                            clang::CharSourceRange  FilenameRange,
                            const clang::FileEntry *File,
                            llvm::StringRef         SearchPath,
                            llvm::StringRef         RelativePath,
                            const clang::Module    *Imported)
    override;

    void moduleImport(clang::SourceLocation  ImportLoc,
                      clang::ModuleIdPath    Path,
                      const clang::Module   *Imported)
    override;

    void EndOfMainFile()
    override;

    void Ident(clang::SourceLocation Loc, const std::string &Str)
    override;

    virtual void PragmaDirective(clang::SourceLocation       Loc,
                                 clang::PragmaIntroducerKind Introducer)
    override;

    void PragmaComment(clang::SourceLocation         Loc,
                       const clang::IdentifierInfo  *Kind,
                       const std::string&            Str)
    override;

    void PragmaDetectMismatch(clang::SourceLocation     Loc,
                              const std::string        &Name,
                              const std::string        &Value)
    override;

    void PragmaDebug(clang::SourceLocation Loc,
                     llvm::StringRef       DebugType)
    override;

    void PragmaMessage(clang::SourceLocation Loc,
                       llvm::StringRef       Namespace,
                       PragmaMessageKind     Kind,
                       llvm::StringRef       Str)
    override;

    void PragmaDiagnosticPush(clang::SourceLocation Loc,
                              llvm::StringRef       Namespace)
    override;

    void PragmaDiagnosticPop(clang::SourceLocation Loc,
                             llvm::StringRef       Namespace)
    override;

    void PragmaDiagnostic(clang::SourceLocation Loc,
                          llvm::StringRef       Namespace,
                          clang::diag::Mapping  Mapping,
                          llvm::StringRef       Str)
    override;

    void PragmaOpenCLExtension(clang::SourceLocation        NameLoc,
                               const clang::IdentifierInfo *Name,
                               clang::SourceLocation        StateLoc,
                               unsigned                     State)
    override;

    void PragmaWarning(clang::SourceLocation Loc,
                       llvm::StringRef       WarningSpec,
                       llvm::ArrayRef<int>   Ids)
    override;

    void PragmaWarningPush(clang::SourceLocation Loc,
                           int                   Level)
    override;

    void PragmaWarningPop(clang::SourceLocation Loc)
    override;

    void MacroExpands(const clang::Token&          MacroNameTok,
                      const clang::MacroDirective *MD,
                      clang::SourceRange           Range,
                      const clang::MacroArgs      *Args)
    override;

    void MacroDefined(const clang::Token&          MacroNameTok,
                      const clang::MacroDirective *MD)
    override;

    void MacroUndefined(const clang::Token&          MacroNameTok,
                        const clang::MacroDirective *MD)
    override;

    void Defined(const clang::Token&          MacroNameTok,
                 const clang::MacroDirective *MD,
                 clang::SourceRange           Range)
    override;

    void SourceRangeSkipped(clang::SourceRange Range)
    override;

    void If(clang::SourceLocation Loc,
            clang::SourceRange    ConditionRange,
            bool                  ConditionValue)
    override;

    void Elif(clang::SourceLocation Loc,
              clang::SourceRange    ConditionRange,
              bool                  ConditionValue,
              clang::SourceLocation IfLoc)
    override;

    void Ifdef(clang::SourceLocation        Loc,
               const clang::Token&          MacroNameTok,
               const clang::MacroDirective *MD)
    override;

    void Ifndef(clang::SourceLocation        Loc,
                const clang::Token&          MacroNameTok,
                const clang::MacroDirective *MD)
    override;

    void Else(clang::SourceLocation Loc, clang::SourceLocation IfLoc)
    override;

    void Endif(clang::SourceLocation Loc, clang::SourceLocation IfLoc)
    override;

    void Context();

    void HandleComment(clang::SourceRange);

private:
    PPObserver(PPObserver const&);
    void operator=(PPObserver const&);

    void do_include_file(clang::SourceLocation, bool, std::string const&);
    void do_open_file(clang::SourceLocation,
                      std::string const &,
                      std::string const &);
    void do_close_file(clang::SourceLocation,
                       std::string const &,
                       std::string const &);
    void do_skip_file(std::string const&, std::string const&);
    void do_file_not_found(std::string const&);
    void
    do_other_file(std::string const &, clang::PPCallbacks::FileChangeReason);
    void do_ident(clang::SourceLocation, std::string const&);
    void do_pragma(clang::SourceLocation, std::string const&);
    void do_macro_expands(clang::Token const &,
                          clang::MacroDirective const *,
                          clang::SourceRange,
                          clang::MacroArgs const *);
    void do_macro_defined(clang::Token const&, clang::MacroDirective const*);
    void do_macro_undefined(clang::Token const&, clang::MacroDirective const*);
    void do_if(clang::SourceLocation, clang::SourceRange);
    void do_elif(clang::SourceLocation, clang::SourceRange);
    void do_ifdef(clang::SourceLocation, clang::Token const&);
    void do_ifndef(clang::SourceLocation, clang::Token const&);
    void do_else(clang::SourceLocation, clang::SourceLocation);
    void do_endif(clang::SourceLocation, clang::SourceLocation);
    void do_comment(clang::SourceRange);
    void do_context();

    std::string get_file(clang::SourceLocation) const;
    clang::SourceManager const* source_manager_;
    std::stack<std::string> files_;
    bool                    connected_;
    Config*                 config_;
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
