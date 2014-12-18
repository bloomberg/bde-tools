// csabase_analyser.cpp                                               -*-C++-*-

#include <csabase_analyser.h>
#include <clang/AST/Decl.h>
#include <clang/AST/DeclBase.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/DeclTemplate.h>
#include <clang/AST/DeclarationName.h>
#include <clang/AST/Expr.h>
#include <clang/AST/Stmt.h>
#include <clang/AST/Type.h>
#include <clang/AST/UnresolvedSet.h>
#include <clang/Basic/DiagnosticIDs.h>
#include <clang/Basic/IdentifierTable.h>
#include <clang/Basic/SourceManager.h>
#include <clang/Frontend/CompilerInstance.h>
#include <clang/Lex/HeaderSearch.h>
#include <clang/Lex/Lexer.h>
#include <clang/Lex/Preprocessor.h>
#include <clang/Rewrite/Core/Rewriter.h>
#include <clang/Sema/Lookup.h>
#include <clang/Sema/Sema.h>
#include <csabase_checkregistry.h>
#include <csabase_config.h>
#include <csabase_debug.h>
#include <csabase_filenames.h>
#include <csabase_location.h>
#include <csabase_ppobserver.h>
#include <csabase_visitor.h>
#include <llvm/ADT/ArrayRef.h>
#include <llvm/ADT/SmallPtrSet.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Path.h>
#include <llvm/Support/Regex.h>
#include <stddef.h>
#include <algorithm>
#include <map>
#include <utility>
#include <csabase_diagnostic_builder.h>
#include <utils/event.hpp>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

csabase::Analyser::Analyser(CompilerInstance& compiler,
                            bool debug,
                            std::vector<std::string> const& config,
                            std::string const& name,
                            std::string const& rewrite_dir,
                            std::string const& rewrite_file)
: d_config(new Config(
      config.size() == 0 ? std::vector<std::string>(1, "load .bdeverify") :
                           config,
      compiler.getSourceManager()))
, tool_name_(name)
, compiler_(compiler)
, d_source_manager(compiler.getSourceManager())
, visitor_(new Visitor())
, context_(0)
, rewriter_(new Rewriter(compiler.getSourceManager(), compiler.getLangOpts()))
, rewrite_dir_(rewrite_dir)
, rewrite_file_(rewrite_file)
{
    compiler_.getPreprocessor().addPPCallbacks(std::unique_ptr<PPCallbacks>(
        new PPObserver(&d_source_manager, d_config.get())));
    compiler_.getPreprocessor().addCommentHandler(
        pp_observer().get_comment_handler());
    CheckRegistry::attach(*this, *visitor_, pp_observer());
}

// -----------------------------------------------------------------------------

csabase::Config const* csabase::Analyser::config() const
{
    return d_config.get();
}

// -----------------------------------------------------------------------------

std::string const& csabase::Analyser::tool_name() const
{
    return tool_name_;
}

// -----------------------------------------------------------------------------

ASTContext const* csabase::Analyser::context() const
{
    return context_;
}

ASTContext* csabase::Analyser::context()
{
    return context_;
}

void csabase::Analyser::context(ASTContext* context)
{
    context_ = context;
    pp_observer().Context();
}

CompilerInstance& csabase::Analyser::compiler()
{
    return compiler_;
}

csabase::PPObserver& csabase::Analyser::pp_observer()
{
    return *static_cast<PPObserver *>(
        compiler_.getPreprocessor().getPPCallbacks());
}

Rewriter& csabase::Analyser::rewriter()
{
    return *rewriter_;
}

std::string const& csabase::Analyser::rewrite_dir() const
{
    return rewrite_dir_;
}

std::string const& csabase::Analyser::rewrite_file() const
{
    return rewrite_file_;
}

clang::tooling::Replacements const& csabase::Analyser::replacements() const
{
    return replacements_;
}

// -----------------------------------------------------------------------------

Sema& csabase::Analyser::sema()
{
    return compiler_.getSema();
}

// -----------------------------------------------------------------------------

namespace
{
    static std::string const source_suffixes[] =
    {
        ".cpp", ".cc", ".cxx", ".C", ".CC", ".c++", ".c"
    };
    const int NSS = sizeof source_suffixes / sizeof *source_suffixes;

    static std::string const header_suffixes[] =
    {
        ".h", ".hpp", ".hxx", ".hh", ".H", ".HH", ".h++"
    };
    const int NHS = sizeof header_suffixes / sizeof *header_suffixes;

}

std::string const& csabase::Analyser::toplevel() const
{
    return toplevel_;
}

std::string const& csabase::Analyser::directory() const
{
    return directory_;
}

std::string const& csabase::Analyser::prefix() const
{
    return prefix_;
}

std::string const& csabase::Analyser::package() const
{
    return package_;
}

std::string const& csabase::Analyser::group() const
{
    return group_;
}

std::string const& csabase::Analyser::component() const
{
    return component_;
}

bool csabase::Analyser::is_source(std::string const& path) const
{
    FileName fn(path);
    for (int i = 0; i < NSS; ++i) {
        if (fn.extension().equals(source_suffixes[i])) {
            return true;                                              // RETURN
        }
    }
    return false;
}

bool csabase::Analyser::is_header(std::string const& path) const
{
    FileName fn(path);
    for (int i = 0; i < NSS; ++i) {
        if (fn.extension().equals(header_suffixes[i])) {
            return true;                                              // RETURN
        }
    }
    return false;
}

void csabase::Analyser::toplevel(std::string const& path)
{
    FileName fn(path);
    toplevel_ = fn.full();
    prefix_ = fn.full();
    for (int i = 0; i < NSS; ++i) {
        if (fn.extension().equals(source_suffixes[i])) {
            prefix_ = fn.prefix();
            break;
        }
    }
    directory_ = fn.directory();
    package_ = fn.package();
    group_ = fn.group();
    component_ = fn.component();
}

bool csabase::Analyser::is_component_header(std::string const& name) const
{
    IsComponentHeader::iterator in = is_component_header_.find(name);
    if (in != is_component_header_.end()) {
        return in->second;
    }

    FileName fn(name);

    for (int i = 0; i < NHS; ++i) {
        if (fn.extension().equals(header_suffixes[i])) {
            if (fn.component() == component_) {
                return is_component_header_[name] = true;             // RETURN
            }
            break;
        }
    }
    return is_component_header_[name] = false;
}

bool csabase::Analyser::is_component_header(SourceLocation loc) const
{
    return is_component_header(get_location(loc).file());
}

bool csabase::Analyser::is_global_package(std::string const& pkg) const
{
    IsGlobalPackage::iterator in = is_global_package_.find(pkg);
    if (in == is_global_package_.end()) {
        llvm::Regex re("(" "^[[:space:]]*" "|" "[^[:alnum:]]" ")" +
                       pkg +
                       "(" "[^[:alnum:]]" "|" "[[:space:]]*$" ")");
        in = is_global_package_.insert(
              std::make_pair(pkg, re.match(config()->value("global_packages")))
             ).first;
    }
    return in->second;
}

bool csabase::Analyser::is_system_header(llvm::StringRef file)
{
    auto i = is_system_header_.find(file);
    if (i != is_system_header_.end()) {
        return i->second;
    }

    const auto& hs = compiler().getPreprocessor().getHeaderSearchInfo();
    for (auto i = hs.system_dir_begin(); i != hs.system_dir_end(); ++i) {
        if (file.startswith(i->getName())) {
            return is_system_header_[file] = true;
        }
    }
    return is_system_header_[file] = false;
}

bool csabase::Analyser::is_system_header(SourceLocation sl)
{
    return is_system_header(manager().getFilename(sl));
}

bool csabase::Analyser::is_global_package() const
{
    return is_global_package(package());
}

bool csabase::Analyser::is_standard_namespace(std::string const& ns) const
{
    IsGlobalPackage::iterator in = is_standard_namespace_.find(ns);
    if (in == is_standard_namespace_.end()) {
        std::string pat = ns;
        for (size_t i = 0; i < pat.size(); ++i) {
            if (pat[i] == ':') {
                pat.insert(i, "(");
                pat.append(")?");
                ++i;
            }
        }
        llvm::Regex re("(" "^[[:space:]]*" "|" "[^[:alnum:]]" ")" +
                       pat +
                       "(" "[^[:alnum:]]" "|" "[[:space:]]*$" ")");
        in = is_standard_namespace_
                 .insert(std::make_pair(
                      ns, re.match(config()->value("standard_namespaces"))))
                 .first;
    }
    return in->second;
}

bool csabase::Analyser::is_component_source(std::string const& file) const
{
    std::string::size_type pos(file.find(toplevel()));
    return pos != file.npos && pos + toplevel().size() == file.size();
}

bool csabase::Analyser::is_component_source(SourceLocation loc) const
{
    return is_component_source(get_location(loc).file());
}

bool csabase::Analyser::is_component(std::string const& file) const
{
    return is_component_source(file)
        || is_component_header(file);
}

bool csabase::Analyser::is_component(SourceLocation loc) const
{
    return is_component(get_location(loc).file());
}

bool csabase::Analyser::is_test_driver() const
{
    //-dk:TODO this should be configurable, e.g. using regexp
    return 6 < toplevel().size()
        && toplevel().substr(toplevel().size() - 6) == ".t.cpp";
}

bool csabase::Analyser::is_main() const
{
    std::string::size_type size(toplevel().size());
    std::string suffix(
        toplevel().substr(size - std::min(size, std::string::size_type(6))));
    return suffix == ".m.cpp" || suffix == ".t.cpp";
}

// -----------------------------------------------------------------------------

csabase::diagnostic_builder
csabase::Analyser::report(SourceLocation where,
                          std::string const& check,
                          std::string const& tag,
                          std::string const& message,
                          bool always,
                          DiagnosticIDs::Level level)
{
    Location location(get_location(where));
    if ((always || is_component(location.file())) &&
        !config()->suppressed(tag, where)) {
        unsigned int id(
            compiler_.getDiagnostics().getDiagnosticIDs()->getCustomDiagID(
                level, tool_name() + tag + ": " + message));
        return csabase::diagnostic_builder(
            compiler_.getDiagnostics().Report(where, id), always);
    }
    return csabase::diagnostic_builder();
}

// -----------------------------------------------------------------------------

SourceManager& csabase::Analyser::manager() const
{
    return compiler_.getSourceManager();
}

llvm::StringRef csabase::Analyser::get_source(SourceRange range, bool exact)
{
    const char *pb = "";
    const char *pe = pb + 1;

    if (range.isValid()) {
        SourceManager& sm(manager());
        SourceLocation b = sm.getFileLoc(range.getBegin());
        SourceLocation e = sm.getFileLoc(range.getEnd());
        SourceLocation t = exact ? e : sm.getFileLoc(
                Lexer::getLocForEndOfToken(
                    e.getLocWithOffset(-1), 0, sm, context()->getLangOpts()));
        if (!t.isValid()) {
            t = e;
        }
        if (   b.isValid()
            && t.isValid()
            && sm.getFileID(b) == sm.getFileID(t)
            && sm.getFileOffset(b) <= sm.getFileOffset(t)) {
            pb = sm.getCharacterData(b);
            pe = sm.getCharacterData(t.isValid() ? t : e);
        }
    }
    return llvm::StringRef(pb, pe - pb);
}

SourceRange csabase::Analyser::get_line_range(SourceLocation loc)
{
    SourceRange range(loc, loc);

    if (loc.isValid()) {
        SourceManager& sm(manager());
        loc = sm.getExpansionLoc(loc);
        FileID fid = sm.getFileID(loc);
        size_t line_num = sm.getExpansionLineNumber(loc);
        range.setBegin(sm.translateLineCol(fid, line_num, 1u));
        range.setEnd(sm.translateLineCol(fid, line_num, ~0u));
    }

    return range;
}

SourceRange csabase::Analyser::get_trim_line_range(SourceLocation loc)
{
    SourceRange range(get_line_range(loc));
    llvm::StringRef line = get_source(range);
    range.setBegin(
        range.getBegin().getLocWithOffset(line.size() - line.ltrim().size()));
    range.setEnd(
        range.getEnd().getLocWithOffset(line.rtrim().size() - line.size()));
    return range;
}

llvm::StringRef csabase::Analyser::get_source_line(SourceLocation loc)
{
    return get_source(get_line_range(loc), true);
}

// -----------------------------------------------------------------------------

csabase::Location csabase::Analyser::get_location(SourceLocation sl) const
{
    return Location(d_source_manager, sl);
}

csabase::Location csabase::Analyser::get_location(Decl const* decl) const
{
    return decl
        ? get_location(decl->getLocation())
        : Location();
}

csabase::Location csabase::Analyser::get_location(Expr const* expr) const
{
    return expr
        ? get_location(expr->getLocStart())
        : Location();
}

csabase::Location csabase::Analyser::get_location(Stmt const* stmt) const
{
    return stmt
        ? get_location(stmt->getLocStart())
        : Location();
}

// -----------------------------------------------------------------------------

void csabase::Analyser::process_decl(Decl const* decl)
{
    visitor_->visit(decl);
}

void csabase::Analyser::process_translation_unit_done()
{
    config()->check_bv_stack(*this);
    onTranslationUnitDone();
}

// -----------------------------------------------------------------------------

namespace
{
    NamedDecl*
    lookup_name(Sema& sema, DeclContext* context, llvm::StringRef name)
    {
        std::string::size_type colons(name.find("::"));
        IdentifierInfo const* info(
            &sema.getASTContext().Idents.get(name.substr(0, colons)));
        DeclarationName declName(info);
        DeclarationNameInfo const nameInfo(declName, SourceLocation());
        LookupResult result(sema, nameInfo,
                                   colons == name.npos
                                   ? Sema::LookupUsingDeclName
                                   : Sema::LookupNestedNameSpecifierName,
                                   Sema::ForRedeclaration);
        result.suppressDiagnostics();

        if (sema.LookupQualifiedName(result, context) &&
            result.begin() != result.end()) {
            if (colons == name.npos || colons == name.size() - 2)
            {
                return *result.begin();
            }
            if (NamespaceDecl* decl =
                    llvm::dyn_cast<NamespaceDecl>(*result.begin())) {
                return lookup_name(sema, decl, name.substr(colons + 2));
            }
        }
        std::string::size_type angle = name.find("<");
        if (angle != name.npos) {
            return lookup_name(sema, context, name.substr(0, angle));
        }
        return 0;
    }

    NamedDecl*
    lookup_name(Sema& sema, std::string const& name)
    {
        return lookup_name(
            sema,
            sema.getASTContext().getTranslationUnitDecl(),
            llvm::StringRef(name).startswith("::") ? name.substr(2) : name);
    }
}

NamedDecl*
csabase::Analyser::lookup_name(std::string const& name)
{
    return ::lookup_name(sema(), name);
}

TypeDecl*
csabase::Analyser::lookup_type(std::string const& name)
{
    NamedDecl* decl = lookup_name(name);
    return decl ? llvm::dyn_cast<TypeDecl>(decl): 0;
}

// ----------------------------------------------------------------------------

bool csabase::Analyser::is_ADL_candidate(Decl const* decl)
    // Return true iff the specified 'decl' is a function or function template
    // with a parameter whose type is declared inside the package namespace.
    // This check is used to determine whether to complain about a "mis-scoped"
    // function declaration.  We wish to allow other top-level namespaces (than
    // the package namespace) to contain function declarations if those
    // functions take arguments whose types are defined in the package
    // namespace, on the suspicion that they are declaring specializations or
    // overloads which will then be found by ADL.  As an additional
    // complication, we also wish to allow legacy 'package_name' constructs, so
    // we check whether the parameter type associated classes are prefixed by
    // the component name.
{
    bool adl = false;
    NamespaceDecl *pspace = lookup_name_as<NamespaceDecl>(
        config()->toplevel_namespace() + "::" + package()
    );
    const FunctionDecl *fd = llvm::dyn_cast<FunctionDecl>(decl);
    if (const FunctionTemplateDecl *ftd =
            llvm::dyn_cast<FunctionTemplateDecl>(decl)) {
        fd = ftd->getTemplatedDecl();
    }
    if (fd) {
        unsigned n = fd->getNumParams();
        for (unsigned i = 0; !adl && i < n; ++i) {
            const ParmVarDecl *pd = fd->getParamDecl(i);
            // Gain access to the protected constructors of Expr.
            struct MyExpr : public Expr {
                MyExpr(QualType t) :
                    Expr(Stmt::NoStmtClass,
                            Stmt::EmptyShell()) {
                        setType(t);
                    }
            } e(pd->getOriginalType().getNonReferenceType());
            llvm::ArrayRef<Expr *> ar(&e);
            Sema::AssociatedNamespaceSet ns;
            Sema::AssociatedClassSet cs;
            sema().FindAssociatedClassesAndNamespaces(
                    fd->getLocation(), ar, ns, cs);
            adl = ns.count(const_cast<NamespaceDecl *>(pspace));

            Sema::AssociatedClassSet::iterator csb = cs.begin();
            Sema::AssociatedClassSet::iterator cse = cs.end();
            while (!adl && csb != cse) {
                std::string s =
                    llvm::StringRef((*csb++)->getNameAsString()).lower();
                adl = s == component() || 0 == s.find(component() + "_");
            }
        }
    }
    return adl;
}

// ----------------------------------------------------------------------------

static llvm::Regex generated("GENERATED FILE -+ DO NOT EDIT");

bool csabase::Analyser::is_generated(SourceLocation loc) const
    // Return true if this is an automatically generated file.  The criterion
    // is a first line containing "GENERATED FILE -- DO NOT EDIT".
{
    loc = d_source_manager.getFileLoc(loc);
    FileID fid = d_source_manager.getFileID(loc);
    llvm::StringRef buf = d_source_manager.getBufferData(fid);
    if (generated.match(buf.split('\n').first)) {
        return true;                                                  // RETURN
    }

    // Note that the bg/eg tags below do not respect preprocessor sections.
    // They can look like
    //..
    //  #if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
    //  #elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
    //  // {{{ BEGIN GENERATED CODE
    //  #else
    //  // }}} END GENERATED CODE
    //  #endif
    //..
    unsigned pos = d_source_manager.getFileOffset(loc);
    static const char bg[] = "\n// {{{ BEGIN GENERATED CODE";
    static const char eg[] = "\n// }}} END GENERATED CODE";
    size_t bpos = buf.npos;
    for (size_t p = 0; (p = buf.find(bg, p)) < pos; ++p) {
        bpos = p;
    }
    return bpos != buf.npos && pos < buf.find(eg, bpos);
}

// ----------------------------------------------------------------------------

std::string
csabase::Analyser::get_rewrite_file(std::string file)
{
    llvm::SmallVector<char, 512> path(
        rewrite_dir_.begin(), rewrite_dir_.end());
    llvm::sys::path::append(path, llvm::sys::path::filename(file));
    return std::string(path.begin(), path.end()) + "-rewritten";
}

// ----------------------------------------------------------------------------

int csabase::Analyser::InsertTextAfter(SourceLocation l, llvm::StringRef s)
{
    d_source_manager.getDecomposedExpansionLoc(l);
    return ReplaceText(l.getLocWithOffset(1), 0, s);
}

int csabase::Analyser::InsertTextBefore(SourceLocation l, llvm::StringRef s)
{
    return ReplaceText(l, 0, s);
}

int csabase::Analyser::RemoveText(SourceRange r)
{
    return ReplaceText(r, "");
}

int csabase::Analyser::RemoveText(SourceLocation l, unsigned n)
{
    return ReplaceText(l, n, "");
}

int
csabase::Analyser::ReplaceText(SourceLocation l, unsigned n, llvm::StringRef s)
{
    l = d_source_manager.getExpansionLoc(l);
    d_source_manager.getDecomposedLoc(l);
    tooling::Replacement r(d_source_manager, l, n, s);
    replacements_.insert(r);
    return 0;
}

int csabase::Analyser::ReplaceText(SourceRange r, llvm::StringRef s)
{
    unsigned n = d_source_manager.getFileOffset(
                     d_source_manager.getExpansionLoc(r.getEnd())) -
                 d_source_manager.getFileOffset(
                     d_source_manager.getExpansionLoc(r.getBegin()));
    return ReplaceText(r.getBegin(), n, s);
}

int csabase::Analyser::ReplaceText(
          llvm::StringRef file, unsigned offset, unsigned n, llvm::StringRef s)
{
    tooling::Replacement r(file, offset, n, s);
    replacements_.insert(r);
    return 0;
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
