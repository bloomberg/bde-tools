// csaaq_inentns.cpp                                                  -*-C++-*-

#include <csabase_analyser.h>
#include <csabase_clang.h>
#include <csabase_config.h>
#include <csabase_debug.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <csabase_report.h>
#include <csabase_visitor.h>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("in-enterprise-namespace");

// ----------------------------------------------------------------------------

namespace
{

struct data
    // Data attached to analyzer for this check.
{
};

struct report : Report<data>
{
    using Report<data>::Report;

    void operator()(const NamedDecl *decl);

    void operator()();
};

void report::operator()(const NamedDecl *decl)
{
    if (!a.is_test_driver() &&
        decl->getLinkageInternal() == Linkage::ExternalLinkage &&
        !decl->isInAnonymousNamespace() &&
        !decl->isInStdNamespace() &&
        !decl->isCXXClassMember() &&
        !a.is_system_header(decl)) {
        const DeclContext *dc = llvm::dyn_cast<NamespaceDecl>(decl);
        if (!dc) {
            dc = decl->getDeclContext()->getEnclosingNamespaceContext();
        }
        if (dc && !dc->isTranslationUnit()) {
            for (;;) {
                auto pdc = dc->getParent()->getEnclosingNamespaceContext();
                if (pdc && !pdc->isTranslationUnit() && pdc != dc) {
                    dc = pdc;
                }
                else {
                    break;
                }
            }
        }
        const NamespaceDecl *nd = llvm::dyn_cast<NamespaceDecl>(dc);
        if (!nd) {
            a.report(decl, check_name, "AQQ01",
                     "Declaration in global, not ::%0 namespace", true)
                << a.config()->toplevel_namespace();
        }
        else if (!nd->isAnonymousNamespace()) {
            std::string ns = nd->getNameAsString();
            if (!a.is_global_package(ns) &&
                !a.is_standard_namespace(ns) &&
                ns != a.config()->toplevel_namespace()) {
                a.report(decl, check_name, "AQQ01",
                         "Declaration in %0, not ::%1 namespace", true)
                    << ns
                    << a.config()->toplevel_namespace();
            }
        }
    }
}

// TranslationUnitDone
void report::operator()()
{
}

void subscribe(Analyser& analyser, Visitor& visitor, PPObserver& observer)
    // Hook up the callback functions.
{
    analyser.onTranslationUnitDone += report(analyser);
    visitor.onNamedDecl            += report(analyser);
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
