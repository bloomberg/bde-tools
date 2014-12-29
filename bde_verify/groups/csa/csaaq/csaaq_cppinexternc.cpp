// csaaq_cppinexternc.cpp                                             -*-C++-*-

#include <clang/Lex/Token.h>

#include <csabase_analyser.h>
#include <csabase_clang.h>
#include <csabase_debug.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <csabase_report.h>
#include <csabase_visitor.h>

#include <llvm/Support/Regex.h>

#include <unordered_map>
#include <unordered_set>

using namespace csabase;
using namespace clang::tooling;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("cpp-in-extern-c");

// ----------------------------------------------------------------------------

namespace
{

std::unordered_set<std::string> special{
    "bsl_stdhdrs_epilogue_recursive.h",
    "bsl_stdhdrs_epilogue.h",
    "bsl_stdhdrs_prologue.h",
};

struct data
    // Data attached to analyzer for this check.
{
    std::map<SourceLocation, std::pair<std::string, bool>>        d_includes;
    std::map<SourceRange, const LinkageSpecDecl *>                d_linkages;
    std::unordered_map<std::string,
                       std::pair<SourceLocation, LinkageSpecDecl::LanguageIDs>>
                                                                  d_types;
    std::unordered_set<SourceLocation>                            d_done;
};

struct report : Report<data>
{
    using Report<data>::Report;

    const LinkageSpecDecl *get_linkage(SourceLocation sl);

    const LinkageSpecDecl *get_local_linkage(SourceLocation sl);

    void operator()(SourceLocation   HashLoc,
                    const Token&     IncludeTok,
                    StringRef        FileName,
                    bool             IsAngled,
                    CharSourceRange  FilenameRange,
                    const FileEntry *File,
                    StringRef        SearchPath,
                    StringRef        RelativePath,
                    const Module    *Imported);

    void operator()(const FileEntry&           ParentFile,
                    const Token&               FilenameTok,
                    SrcMgr::CharacteristicKind FileType);

    void operator()(SourceLocation        Loc,
                    const Token&          MacroNameTok,
                    const MacroDirective *MD);

    void operator()(const Token&          MacroNameTok,
                    const MacroDirective *MD,
                    SourceRange           Range);

    void operator()(SourceRange Range);

    void operator()(const Decl *decl);

    void set_lang(SourceLocation sl, LinkageSpecDecl::LanguageIDs lang);

    void operator()(const FunctionDecl *decl);

    void operator()(const VarDecl *decl);

    void operator()(const LinkageSpecDecl *decl);

    void operator()(const Stmt *stmt);

    void operator()();
};

const LinkageSpecDecl *report::get_linkage(SourceLocation sl)
{
    const LinkageSpecDecl *result = 0;
    for (const auto& r : d_data.d_linkages) {
        if (!m.isBeforeInTranslationUnit(sl, r.first.getBegin()) &&
            !m.isBeforeInTranslationUnit(r.first.getEnd(), sl)) {
            result = r.second;
        }
    }
    return result;
}

const LinkageSpecDecl *report::get_local_linkage(SourceLocation sl)
{
    const LinkageSpecDecl *result = 0;
    for (const auto& r : d_data.d_linkages) {
        if (!m.isBeforeInTranslationUnit(sl, r.first.getBegin()) &&
            !m.isBeforeInTranslationUnit(r.first.getEnd(), sl) &&
            m.getFileID(m.getExpansionLoc(sl)) ==
            m.getFileID(m.getExpansionLoc(r.first.getBegin()))) {
            result = r.second;
        }
    }
    return result;
}

// InclusionDirective
void report::operator()(SourceLocation   HashLoc,
                        const Token&     IncludeTok,
                        StringRef        FileName,
                        bool             IsAngled,
                        CharSourceRange  FilenameRange,
                        const FileEntry *File,
                        StringRef        SearchPath,
                        StringRef        RelativePath,
                        const Module    *Imported)
{
    d_data.d_includes.insert({FilenameRange.getBegin(), {FileName, false}});
}

// FileSkipped
void report::operator()(const FileEntry&           ParentFile,
                        const Token&               FilenameTok,
                        SrcMgr::CharacteristicKind FileType)
{
    SourceLocation sl = m.getExpansionLoc(FilenameTok.getLocation());
    if (!special.count(llvm::sys::path::filename(m.getFilename(sl))))
    {
        llvm::StringRef file(
            FilenameTok.getLiteralData() + 1, FilenameTok.getLength() - 2);
        d_data.d_includes.insert({sl, {file, true}});
    }
}

// SourceRangeSkipped
void report::operator()(SourceRange Range)
{
    SourceLocation sl = Range.getBegin();
    if (!special.count(llvm::sys::path::filename(m.getFilename(sl)))) {
        llvm::StringRef s = d_analyser.get_source(Range);
        static llvm::Regex r(" *ifn?def *INCLUDED_.*[[:space:]]+"
                             "# *include +[<\"]([^\">]*)[\">]");
        llvm::SmallVector<llvm::StringRef, 7> matches;
        if (r.match(s, &matches) && s.find(matches[0]) == 0) {
            d_data.d_includes.insert(
                {sl.getLocWithOffset(s.find(matches[1])), {matches[1], true}});
        }
    }
}

// Ifdef/Ifndef
void report::operator()(SourceLocation        Loc,
                        const Token&          MacroNameTok,
                        const MacroDirective *MD)
{
#if 0
    llvm::StringRef name = llvm::sys::path::filename(m.getFilename(Loc));
    if (MacroNameTok.getIdentifierInfo()->getName() == "__cplusplus" &&
        d_data.d_types[name].second != LinkageSpecDecl::lang_c) {
        d_data.d_types[name] = std::make_pair(Loc, LinkageSpecDecl::lang_c);
    }
#endif
}

// Defined
void report::operator()(const Token&          MacroNameTok,
                        const MacroDirective *MD,
                        SourceRange           Range)
{
#if 0
    SourceLocation Loc = Range.getBegin();
    llvm::StringRef name = llvm::sys::path::filename(m.getFilename(Loc));
    if (MacroNameTok.getIdentifierInfo()->getName() == "__cplusplus" &&
        d_data.d_types[name].second != LinkageSpecDecl::lang_c) {
        d_data.d_types[name] = std::make_pair(Loc, LinkageSpecDecl::lang_c);
    }
#endif
}

void report::set_lang(SourceLocation sl, LinkageSpecDecl::LanguageIDs lang)
{
    SourceLocation osl = sl;
    while (sl.isValid() && !get_local_linkage(sl)) {
        llvm::StringRef name(llvm::sys::path::filename(m.getFilename(sl)));
        if (!special.count(name) && !d_data.d_types[name].second) {
            d_data.d_types[name] = std::make_pair(osl, lang);
        }
        sl = m.getIncludeLoc(m.getFileID(sl));
    }
}

void report::operator()(const FunctionDecl *decl)
{
    SourceLocation sl = m.getExpansionLoc(decl->getLocation());
    if (decl->isGlobal() &&
        !decl->isCXXClassMember() &&
        !decl->isExternC() &&
        !get_local_linkage(sl)) {
        set_lang(sl, LinkageSpecDecl::lang_cxx);
    }
}

void report::operator()(const VarDecl *decl)
{
    SourceLocation sl = m.getExpansionLoc(decl->getLocation());
    if (decl->hasExternalStorage() &&
        !decl->isCXXClassMember() &&
        !decl->isExternC() &&
        !get_local_linkage(sl)) {
        set_lang(sl, LinkageSpecDecl::lang_cxx);
    }
}

void report::operator()(const LinkageSpecDecl *decl)
{
    if (decl->hasBraces()) {
        d_data.d_linkages[decl->getSourceRange()] = decl;
    }
#if 0
    if (decl->getLanguage() == LinkageSpecDecl::lang_cxx) {
        SourceLocation sl = m.getExpansionLoc(decl->getLocation());
        set_lang(sl, LinkageSpecDecl::lang_cxx);
    }
#endif
}

#if 0
void report::operator()(const FunctionDecl *decl)
{
    if (decl->isOverloadedOperator() ||
        decl->isInlined() ||
        decl->getTemplatedKind() != FunctionDecl::TK_NonTemplate) {
        SourceLocation sl = m.getExpansionLoc(decl->getLocation());
        set_lang(sl, LinkageSpecDecl::lang_cxx);
    }
}
#endif

void report::operator()(const Decl *decl)
{
    switch (decl->getKind()) {
      //case Decl::AccessSpec:
      //case Decl::ClassScopeFunctionSpecialization:
      //case Decl::Friend:
      //case Decl::FriendTemplate:
      //case Decl::Namespace:
      //case Decl::NamespaceAlias:
      case Decl::ClassTemplate:
      case Decl::FunctionTemplate:
      //case Decl::TypeAliasTemplate:
      case Decl::VarTemplate:
      //case Decl::TemplateTemplateParm:
      //case Decl::CXXRecord:
      case Decl::ClassTemplateSpecialization:
      case Decl::ClassTemplatePartialSpecialization:
      //case Decl::TemplateTypeParm:
      //case Decl::TypeAlias:
      //case Decl::UnresolvedUsingTypename:
      //case Decl::Using:
      //case Decl::UsingDirective:
      //case Decl::UsingShadow:
      //case Decl::CXXMethod:
      //case Decl::CXXConstructor:
      //case Decl::CXXConversion:
      //case Decl::CXXDestructor:
      //case Decl::NonTypeTemplateParm:
      //case Decl::VarTemplateSpecialization:
      //case Decl::UnresolvedUsingValue:
      {
        SourceLocation sl = m.getExpansionLoc(decl->getLocation());
        set_lang(sl, LinkageSpecDecl::lang_cxx);
      }
      default:
        ;
    }
}

void report::operator()(const Stmt *stmt)
{
#if 0
    switch (stmt->getStmtClass()) {
      case Stmt::CXXCatchStmtClass:
      case Stmt::CXXForRangeStmtClass:
      case Stmt::CXXTryStmtClass:
      case Stmt::CXXBindTemporaryExprClass:
      case Stmt::CXXBoolLiteralExprClass:
      case Stmt::CXXConstructExprClass:
      case Stmt::CXXTemporaryObjectExprClass:
      case Stmt::CXXDefaultArgExprClass:
      case Stmt::CXXDefaultInitExprClass:
      case Stmt::CXXDeleteExprClass:
      case Stmt::CXXDependentScopeMemberExprClass:
      case Stmt::CXXNewExprClass:
      case Stmt::CXXNoexceptExprClass:
      case Stmt::CXXNullPtrLiteralExprClass:
      case Stmt::CXXPseudoDestructorExprClass:
      case Stmt::CXXScalarValueInitExprClass:
      case Stmt::CXXStdInitializerListExprClass:
      case Stmt::CXXThisExprClass:
      case Stmt::CXXThrowExprClass:
      case Stmt::CXXTypeidExprClass:
      case Stmt::CXXUnresolvedConstructExprClass:
      case Stmt::CXXUuidofExprClass:
      case Stmt::CXXMemberCallExprClass:
      case Stmt::CXXOperatorCallExprClass:
      case Stmt::UserDefinedLiteralClass:
      case Stmt::CXXFunctionalCastExprClass:
      case Stmt::CXXConstCastExprClass:
      case Stmt::CXXDynamicCastExprClass:
      case Stmt::CXXReinterpretCastExprClass:
      case Stmt::CXXStaticCastExprClass:
      case Stmt::FunctionParmPackExprClass:
      case Stmt::LambdaExprClass:
      case Stmt::UnresolvedLookupExprClass:
      case Stmt::UnresolvedMemberExprClass:
      case Stmt::PackExpansionExprClass:
      case Stmt::SizeOfPackExprClass:
      case Stmt::SubstNonTypeTemplateParmExprClass:
      case Stmt::SubstNonTypeTemplateParmPackExprClass: {
        SourceLocation sl = m.getExpansionLoc(stmt->getLocStart());
        set_lang(sl, LinkageSpecDecl::lang_cxx);
      }
      default:
        ;
    }
#endif
}

// TranslationUnitDone
void report::operator()()
{
    for (const auto& f : d_data.d_includes) {
        const LinkageSpecDecl *lsd = get_linkage(f.first);
        if (!lsd ||
            lsd->getLanguage() != LinkageSpecDecl::lang_c ||
            d_data.d_types[f.second.first].second !=
                LinkageSpecDecl::lang_cxx) {
            continue;
        }
        SourceLocation sl = m.getExpansionLoc(f.first);
        FileID lfid = m.getFileID(m.getExpansionLoc(lsd->getLocation()));
        while (sl.isValid() && m.getFileID(sl) != lfid) {
            sl = m.getIncludeLoc(m.getFileID(sl));
        }
        if (sl.isValid() && d_data.d_done.count(sl)) {
            continue;
        }
        d_analyser.report(f.first, check_name, "PC01",
                      "C++ header included within C linkage specification",
                          true);
        d_analyser.report(lsd->getLocation(), check_name, "PC01",
                          "C linkage specification here",
                          true, DiagnosticIDs::Note);
        if (sl.isValid() && sl != f.first) {
            d_data.d_done.insert(sl);
            d_analyser.report(sl, check_name, "PC01",
                              "Top level include within C linkage here",
                              true, DiagnosticIDs::Note);
        }
        d_analyser.report(d_data.d_types[f.second.first].first,
                          check_name, "PC01",
                          "Declaration with C++ linkage here",
                          true, DiagnosticIDs::Note);
    }
}

void subscribe(Analyser& analyser, Visitor& visitor, PPObserver& observer)
    // Hook up the callback functions.
{
    observer.onPPInclusionDirective += report(analyser,
                                                observer.e_InclusionDirective);
    observer.onPPFileSkipped        += report(analyser,
                                                observer.e_FileSkipped);
    observer.onPPSourceRangeSkipped += report(analyser,
                                                observer.e_SourceRangeSkipped);
    observer.onPPIfdef              += report(analyser, observer.e_Ifdef);
    observer.onPPIfndef             += report(analyser, observer.e_Ifndef);
    observer.onPPDefined            += report(analyser, observer.e_Defined);
    analyser.onTranslationUnitDone  += report(analyser);
    visitor.onDecl                  += report(analyser);
    visitor.onFunctionDecl          += report(analyser);
    visitor.onLinkageSpecDecl       += report(analyser);
    visitor.onStmt                  += report(analyser);
}

}  // close anonymous namespace

// ----------------------------------------------------------------------------

static RegisterCheck c1(check_name, &subscribe);

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
