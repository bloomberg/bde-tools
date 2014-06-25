// csamisc_calls.cpp                                                  -*-C++-*-

#include <csabase_analyser.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <fstream>
#include <sstream>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("calls");

// -----------------------------------------------------------------------------

namespace
{
    struct files
    {
        std::ofstream d_header;
        std::ofstream d_source;
    };
}

// -----------------------------------------------------------------------------

static void
process(Analyser& analyser, Expr const* expr, Decl const* decl)
{
    if (const FunctionDecl* function =
            decl ? llvm::dyn_cast<FunctionDecl>(decl) : 0) {
        function = function->getCanonicalDecl();
        std::string name;
        PrintingPolicy policy(analyser.context()->getLangOpts());
        function->getNameForDiagnostic(name, policy, true);

        std::ostringstream out;
        out << name << "(";
        for (FunctionDecl::param_const_iterator it(function->param_begin()),
             end(function->param_end());
             it != end;
             ++it) {
            if (it != function->param_begin()) {
                out << ", ";
            }
            ParmVarDecl const* param(*it);
            out << param->getType().getAsString();
            if (param->isParameterPack()) {
                out << "...";
            }
        }
        out << ")";
        CXXMethodDecl const* method(llvm::dyn_cast<CXXMethodDecl>(function));
        if (method && !method->isStatic()) {
            if (method->getTypeQualifiers() & Qualifiers::Const) {
                out << " const";
            }
            if (method->getTypeQualifiers() & Qualifiers::Volatile) {
                out << " volatile";
            }
            if (method->getTypeQualifiers() & Qualifiers::Restrict) {
                out << " restrict";
            }
        }

        name += out.str();

        //-dk:TODO analyser.report(expr, check_name, "function decl: '%0'")
        //-dk:TODO     << expr->getSourceRange()
        //-dk:TODO     << out.str()
            ;
    }
    else {
        analyser.report(expr, check_name, "UF01", "Unresolved function call")
            << expr->getSourceRange();
    }
}

// -----------------------------------------------------------------------------

static void calls(Analyser& analyser, CallExpr const* expr)
{
    process(analyser, expr, expr->getCalleeDecl());
}

// -----------------------------------------------------------------------------

static void ctors(Analyser& analyser, CXXConstructExpr const* expr)
{
    process(analyser, expr, expr->getConstructor());
}

// -----------------------------------------------------------------------------

static void open_file(Analyser& analyser,
                      SourceLocation where,
                      std::string const&,
                      std::string const& name)
{
    // llvm::errs() << "open_file(" << name << "): " <<
    // analyser.get_location(where) << "\n";
    //analyser.report(where, check_name, "open file: '%0'") << name;
}

static void close_file(Analyser& analyser,
                       SourceLocation where,
                       std::string const&,
                       std::string const& name)
{
    //llvm::errs() << "close_file(" << name << ")\n";
    //analyser.report(where, check_name, "close file: '%0'") << name;
}

// -----------------------------------------------------------------------------

namespace
{
    template <typename T>
    struct analyser_binder
    {
        analyser_binder(
            void (*function)(Analyser&, SourceLocation, T, std::string const&),
            Analyser& analyser)
            : function_(function), analyser_(analyser)
        {
        }
        void
        operator()(SourceLocation where, T arg, std::string const& name) const
        {
            function_(analyser_, where, arg, name);
        }
        void (*function_)(Analyser&, SourceLocation, T, std::string const&);
        Analyser& analyser_;
    };
}

// -----------------------------------------------------------------------------

static void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
{
    observer.onOpenFile +=
        analyser_binder<std::string const&>(open_file, analyser);
    observer.onCloseFile +=
        analyser_binder<std::string const&>(close_file, analyser);
}

// -----------------------------------------------------------------------------

static RegisterCheck register_observer(check_name, &subscribe);
static RegisterCheck register_calls(check_name, &calls);
static RegisterCheck register_ctors(check_name, &ctors);

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
