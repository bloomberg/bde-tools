// csabase_analyser.h                                                 -*-C++-*-

#ifndef INCLUDED_CSABASE_ANALYSER
#define INCLUDED_CSABASE_ANALYSER

#include <clang/AST/ASTContext.h>
#include <clang/Basic/Diagnostic.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_attachments.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_location.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/Support/Casting.h>
#include <map>
#include <memory>
#include <string>
#include <utils/event.hpp>
#include <vector>

namespace clang { class CompilerInstance; }
namespace clang { class Decl; }
namespace clang { class Expr; }
namespace clang { class NamedDecl; }
namespace clang { class Rewriter; }
namespace clang { class Sema; }
namespace clang { class SourceManager; }
namespace clang { class Stmt; }
namespace clang { class TypeDecl; }
namespace csabase { class Config; }
namespace csabase { class PPObserver; }
namespace csabase { class Visitor; }

// -----------------------------------------------------------------------------

namespace csabase
{
class Analyser : public Attachments
{
  public:
    Analyser(clang::CompilerInstance& compiler,
             bool debug,
             std::vector<std::string> const& config,
             std::string const& name,
             std::string const& rewrite_dir);
    ~Analyser();

    Config const* config() const;
    std::string const& tool_name() const;

    clang::ASTContext*       context();
    clang::ASTContext const* context() const;
    void                     context(clang::ASTContext*);
    clang::CompilerInstance& compiler();
    clang::Sema&             sema();
    clang::Rewriter&         rewriter();

    std::string const& toplevel() const;
    std::string const& directory() const;
    std::string const& prefix() const;
    std::string const& group() const;
    std::string const& package() const;
    std::string const& component() const;
    std::string const& rewrite_dir() const;
    void               toplevel(std::string const&);
    bool               is_component_header(std::string const&) const;
    bool               is_component_header(clang::SourceLocation) const;
    bool               is_component_source(std::string const&) const;
    bool               is_component_source(clang::SourceLocation) const;
    bool               is_component(clang::SourceLocation) const;
    bool               is_component(std::string const&) const;
    template <typename T> bool is_component(T const*);
    template <typename T> bool is_component_header(T const*);
    template <typename T> bool is_component_source(T const*);
    bool               is_test_driver() const;
    bool               is_main() const;
    bool               is_standard_namespace(std::string const&) const;
    bool               is_global_package() const;
    bool               is_global_package(std::string const&) const;
    bool               is_ADL_candidate(clang::Decl const*);
    bool               is_generated(clang::SourceLocation) const;

    diagnostic_builder report(clang::SourceLocation where,
                                    std::string const& check,
                                    std::string const& tag,
                                    std::string const& message,
                                    bool always = false,
                                    clang::DiagnosticsEngine::Level level =
                                        clang::DiagnosticsEngine::Warning);

    template <typename T>
    diagnostic_builder report(T where,
                              std::string const& check,
                              std::string const& tag,
                              std::string const& message,
                              bool always = false,
                              clang::DiagnosticsEngine::Level level =
                                  clang::DiagnosticsEngine::Warning);

    clang::SourceManager& manager() const;
    llvm::StringRef         get_source(clang::SourceRange, bool exact = false);
    clang::SourceRange      get_line_range(clang::SourceLocation);
    clang::SourceRange      get_trim_line_range(clang::SourceLocation);
    llvm::StringRef         get_source_line(clang::SourceLocation);
    Location get_location(clang::SourceLocation) const;
    Location get_location(clang::Decl const*) const;
    Location get_location(clang::Expr const*) const;
    Location get_location(clang::Stmt const*) const;

    template <typename InIt> void process_decls(InIt, InIt);
    void process_decl(clang::Decl const*);
    void process_translation_unit_done();
    utils::event<void()> onTranslationUnitDone;

    clang::NamedDecl* lookup_name(std::string const& name);
    clang::TypeDecl*  lookup_type(std::string const& name);
    template <typename T> T* lookup_name_as(std::string const& name);

    bool hasContext() const { return context_; }

    template <typename Parent, typename Node>
    const Parent *get_parent(const Node *node);
        // Return a pointer to the object of the specified 'Parent' type which
        // is the nearest ancestor of the specified 'node' of 'Node' type, and
        // 0 if there is no such object.

private:
    Analyser(Analyser const&);
    void operator= (Analyser const&);
        
    std::auto_ptr<Config>                 d_config;
    std::string                           tool_name_;
    clang::CompilerInstance&              compiler_;
    clang::SourceManager const&           d_source_manager;
    std::auto_ptr<Visitor>                visitor_;
    PPObserver*                           pp_observer_;
    clang::ASTContext*                    context_;
    clang::Rewriter*                      rewriter_;
    std::string                           toplevel_;
    std::string                           directory_;
    std::string                           prefix_;
    std::string                           group_;
    std::string                           package_;
    std::string                           component_;
    std::string                           rewrite_dir_;
    typedef std::map<std::string, bool>   IsComponentHeader;
    mutable IsComponentHeader             is_component_header_;
    typedef std::map<std::string, bool>   IsGlobalPackage;
    mutable IsGlobalPackage               is_global_package_;
    typedef std::map<std::string, bool>   IsStandardNamespace;
    mutable IsStandardNamespace           is_standard_namespace_;
};

// -----------------------------------------------------------------------------

template <typename InIt>
inline
void Analyser::process_decls(InIt it, InIt end)
{
    while (it != end) {
        process_decl(*it++);
    }
}

template <typename T>
inline
diagnostic_builder Analyser::report(
    T where,
    std::string const & check,
    std::string const & tag,
    std::string const & message,
    bool always,
    clang::DiagnosticsEngine::Level level)
{
    return report(
        get_location(where).location(), check, tag, message, always, level);
}

// -----------------------------------------------------------------------------

template <typename T>
inline
bool Analyser::is_component(T const* value)
{
    return is_component(get_location(value).file());
}

template <typename T>
inline
bool Analyser::is_component_header(T const* value)
{
    return is_component_header(get_location(value).file());
}

template <typename T>
inline
bool Analyser::is_component_source(T const* value)
{
    return is_component_source(get_location(value).file());
}

template <typename T>
inline
T* Analyser::lookup_name_as(const std::string& name)
{
    clang::NamedDecl* nd = lookup_name(name);
    return nd ? llvm::dyn_cast<T>(nd) : 0;
}

template <typename Parent, typename Node>
inline
const Parent* Analyser::get_parent(const Node* node)
{
    for (clang::ASTContext::ParentVector pv = context()->getParents(*node);
         pv.size() >= 1;
         pv = context()->getParents(pv[0])) {
        if (const Parent* p = pv[0].get<Parent>()) {
            return p;                                                 // RETURN
        }
    }
    return 0;
}
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
