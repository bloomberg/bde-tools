// csabase_abstractvisitor.h                                          -*-C++-*-

#ifndef INCLUDED_CSABASE_ABSTRACTVISITOR
#define INCLUDED_CSABASE_ABSTRACTVISITOR

#include <clang/AST/DeclVisitor.h>
#include <clang/AST/StmtVisitor.h>

namespace clang { class Decl; }
namespace clang { class DeclContext; }
namespace clang { class Stmt; }
namespace clang { struct StmtRange; }

// -----------------------------------------------------------------------------

namespace csabase
{
class AbstractVisitor:
    public clang::DeclVisitor<AbstractVisitor>,
    public clang::StmtVisitor<AbstractVisitor>
{
public:
    virtual ~AbstractVisitor();

    void visit(clang::Decl const*);
    void visit(clang::Stmt const*);

#define DECL(CLASS, BASE)                                               \
    virtual void do_visit(clang::CLASS##Decl const*);                   \
    void process_decl(clang::CLASS##Decl*, bool nest = false);          \
    void Visit##CLASS##Decl (clang::CLASS##Decl*);
DECL(,void)
#include "clang/AST/DeclNodes.inc"  // IWYU pragma: keep

#define STMT(CLASS, BASE)                                      \
    virtual void do_visit(clang::CLASS const*);                \
    void process_stmt(clang::CLASS*, bool nest = false);       \
    void Visit##CLASS(clang::CLASS*);
STMT(Stmt,void)
#include "clang/AST/StmtNodes.inc"  // IWYU pragma: keep

    void visit_decl(clang::Decl const*);
    void visit_stmt(clang::Stmt const*);
    void visit_context(void const*);
    void visit_context(clang::DeclContext const*);
    void visit_children(clang::StmtRange const&);
    template <typename Children> void visit_children(Children const&);
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
