// csabase_abstractvisitor.cpp                                        -*-C++-*-

#include <csabase_abstractvisitor.h>
#include <clang/AST/Decl.h>
#include <clang/AST/DeclBase.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/DeclFriend.h>
#include <clang/AST/DeclObjC.h>
#include <clang/AST/DeclOpenMP.h>
#include <clang/AST/DeclTemplate.h>
#include <clang/AST/Expr.h>
#include <clang/AST/ExprCXX.h>
#include <clang/AST/ExprObjC.h>
#include <clang/AST/Stmt.h>
#include <clang/AST/StmtCXX.h>
#include <clang/AST/StmtIterator.h>
#include <clang/AST/StmtObjC.h>
#include <clang/AST/StmtOpenMP.h>
#include <csabase_debug.h>
#include <algorithm>
#include <functional>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

csabase::AbstractVisitor::~AbstractVisitor()
{
}

// -----------------------------------------------------------------------------
// Entry points to visit the AST.

void csabase::AbstractVisitor::visit_decl(Decl const* decl)
{
    DeclVisitor<AbstractVisitor>::Visit(const_cast<Decl*>(decl));
}

void csabase::AbstractVisitor::visit(Decl const* decl)
{
    visit_decl(decl);
}

void csabase::AbstractVisitor::visit_stmt(Stmt const* stmt)
{
    if (stmt) {
        StmtVisitor<AbstractVisitor>::Visit(const_cast<Stmt*>(stmt));
    }
}

void csabase::AbstractVisitor::visit(Stmt const* stmt)
{
    visit_stmt(stmt);
}

// -----------------------------------------------------------------------------

void csabase::AbstractVisitor::visit_context(void const*)
{
}

void csabase::AbstractVisitor::visit_context(DeclContext const* context)
{
    Debug d1("process DeclContext");
    std::for_each(
        context->decls_begin(),
        context->decls_end(),
        std::bind1st(std::mem_fun(&AbstractVisitor::visit_decl), this));
}

// -----------------------------------------------------------------------------

template <typename DECL>
static void process_decl(AbstractVisitor* visitor, DECL *decl)
{
}

// -----------------------------------------------------------------------------

static void
process_decl(AbstractVisitor* visitor, NamespaceDecl* decl)
{
    visitor->visit_context(decl);
}

// -----------------------------------------------------------------------------

static void
process_decl(AbstractVisitor* visitor, VarDecl* decl)
{
    if (Expr* init = decl->getInit())
    {
        visitor->visit(init);
    }
}

// -----------------------------------------------------------------------------

static void
process_decl(AbstractVisitor* visitor, FunctionDecl* decl)
{
    Debug d1("process definition FunctionDecl");
    if (decl->getDescribedFunctionTemplate()) {
        visitor->visit(decl->getDescribedFunctionTemplate());
    }

    // Note that due to the potential use of '-fdelayed-template-parsing' in
    // Windows, it is possible for 'decl->hasBody()' to return 'true' but for
    // 'decl->getBody()' to return a null pointer.
    if (decl->isThisDeclarationADefinition() && decl->getBody())
    {
        visitor->visit(decl->getBody());
    }
}

// -----------------------------------------------------------------------------

static void
process_decl(AbstractVisitor* visitor, TagDecl* decl)
{
    visitor->visit_context(decl);
}

// -----------------------------------------------------------------------------

static void
process_decl(AbstractVisitor* visitor, BlockDecl* decl)
{
    visitor->visit_context(decl);
}

// -----------------------------------------------------------------------------

static void
process_decl(AbstractVisitor* visitor, CXXRecordDecl* decl)
{
    Debug d("process_decl(..., CXXRecordDecl)");
}

// -----------------------------------------------------------------------------

static void
process_decl(AbstractVisitor* visitor, LinkageSpecDecl* decl)
{
    if (decl->hasBraces())
    {
        visitor->visit_context(decl);
    }
}

static void
process_decl(AbstractVisitor* visitor, ClassTemplateDecl* decl)
{
    Debug d("ClassTemplateDecl");
    visitor->visit(decl->getTemplatedDecl());
}

// -----------------------------------------------------------------------------

void
csabase::AbstractVisitor::visit_children(StmtRange const& range)
{
    std::for_each(
        range.first,
        range.second,
        std::bind1st(std::mem_fun(&AbstractVisitor::visit_stmt), this));
}

template <typename Children>
void csabase::AbstractVisitor::visit_children(Children const& children)
{
    std::for_each(
        children.begin(),
        children.end(),
        std::bind1st(std::mem_fun(&AbstractVisitor::visit_stmt), this));
}

// -----------------------------------------------------------------------------

template <typename Statement>
static void
process_stmt(AbstractVisitor* visitor, Statement* stmt)
{
}

// -----------------------------------------------------------------------------

static void process_stmt(AbstractVisitor* visitor, DeclStmt* stmt)
{
    std::for_each(
        stmt->decl_begin(),
        stmt->decl_end(),
        std::bind1st(std::mem_fun(&AbstractVisitor::visit_decl), visitor));
}

// -----------------------------------------------------------------------------

void csabase::AbstractVisitor::do_visit(Decl const*)
{
}

void csabase::AbstractVisitor::process_decl(Decl* decl, bool nest)
{
    Debug d("Decl", nest);
    do_visit(decl);
    ::process_decl(this, decl);
}

void csabase::AbstractVisitor::VisitDecl(Decl* decl)
{
    process_decl(decl, true);
}

// -----------------------------------------------------------------------------

#define DECL(CLASS, BASE)                                                     \
    void csabase::AbstractVisitor::do_visit(CLASS##Decl const*)               \
    {                                                                         \
    }                                                                         \
    void csabase::AbstractVisitor::process_decl(CLASS##Decl* decl, bool nest) \
    {                                                                         \
        Debug d(#CLASS "Decl (gen)", nest);                                   \
        do_visit(decl);                                                       \
        ::process_decl(this, decl);                                           \
        process_decl(static_cast<BASE*>(decl), false);                        \
    }                                                                         \
    void csabase::AbstractVisitor::Visit##CLASS##Decl(CLASS##Decl* decl)      \
    {                                                                         \
        process_decl(decl, true);                                             \
    }
#include "clang/AST/DeclNodes.inc"  // IWYU pragma: keep

// -----------------------------------------------------------------------------

void csabase::AbstractVisitor::do_visit(Stmt const*)
{
}

void csabase::AbstractVisitor::process_stmt(Stmt* stmt, bool nest)
{
    Debug d("Stmt", nest);
    do_visit(stmt);
    ::process_stmt(this, stmt);
}

void csabase::AbstractVisitor::VisitStmt(Stmt* stmt)
{
    process_stmt(stmt, true);
}

// -----------------------------------------------------------------------------

#define STMT(CLASS, BASE)                                               \
    void csabase::AbstractVisitor::do_visit(CLASS const*)               \
    {                                                                   \
    }                                                                   \
    void csabase::AbstractVisitor::process_stmt(CLASS* stmt, bool nest) \
    {                                                                   \
        Debug d(#CLASS " (stmt)", nest);                                \
        do_visit(stmt);                                                 \
        if (nest) {                                                     \
            visit_children(stmt->children());                           \
        }                                                               \
        ::process_stmt(this, stmt);                                     \
        process_stmt(static_cast<BASE*>(stmt), false);                  \
    }                                                                   \
    void csabase::AbstractVisitor::Visit##CLASS(CLASS* stmt)            \
    {                                                                   \
        process_stmt(stmt, true);                                       \
    }
#include "clang/AST/StmtNodes.inc"  // IWYU pragma: keep

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
