// csabase_tool.cpp                                                   -*-C++-*-

#include <csabase_tool.h>
#include <clang/Basic/Diagnostic.h>
#include <clang/Basic/DiagnosticIDs.h>
#include <clang/Basic/DiagnosticOptions.h>
#include <clang/Frontend/CompilerInstance.h>
#include <clang/Frontend/CompilerInvocation.h>
#include <clang/Frontend/FrontendDiagnostic.h>  // IWYU pragma: keep
// IWYU pragma: no_include <clang/Basic/DiagnosticFrontendKinds.inc>
#include <clang/Frontend/TextDiagnosticBuffer.h>
#include <clang/FrontendTool/Utils.h>
#include <clang/Tooling/Tooling.h>              // IWYU pragma: keep
#include <llvm/ADT/ArrayRef.h>
#include <llvm/ADT/IntrusiveRefCntPtr.h>
#include <llvm/ADT/OwningPtr.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/Support/Allocator.h>
#include <llvm/Support/CommandLine.h>
#include <llvm/Support/Compiler.h>
#include <llvm/Support/ErrorHandling.h>
#include <llvm/Support/ManagedStatic.h>
#include <llvm/Support/PrettyStackTrace.h>
#include <llvm/Support/Process.h>
#include <llvm/Support/Signals.h>
#include <llvm/Support/TargetSelect.h>
#include <stdlib.h>
#include <set>
#include <string>
#include <utility>

using namespace clang;
using namespace clang::tooling;
using namespace llvm;

static void LLVMErrorHandler(void *UserData, const std::string &Message,
                             bool GenCrashDiag) {
    DiagnosticsEngine &Diags = *static_cast<DiagnosticsEngine*>(UserData);
    Diags.Report(diag::err_fe_error_backend) << Message;
    llvm::sys::RunInterruptHandlers();
    exit(GenCrashDiag ? 70 : 1);
}

namespace {
    class StringSetSaver : public cl::StringSaver {
      public:
        const char *SaveString(const char *Str) LLVM_OVERRIDE {
            return Storage.insert(Str).first->c_str();
        }
      private:
        std::set<std::string> Storage;
    };
}

// -----------------------------------------------------------------------------

int csabase::run(int argc_, const char **argv_)
{
    sys::PrintStackTraceOnErrorSignal();
    PrettyStackTraceProgram X(argc_, argv_);

    SmallVector<const char *, 1024> argv;
    SpecificBumpPtrAllocator<char>  ArgAllocator;
    StringSetSaver                  Saver;

    sys::Process::GetArgumentVector(argv,
                                    ArrayRef<const char *>(argv_, argc_),
                                    ArgAllocator);

    cl::ExpandResponseFiles(Saver, cl::TokenizeGNUCommandLine, argv);

    argv.insert(argv.begin() == argv.end() ? argv.begin() : argv.begin() + 1,
                "-xc++");

    OwningPtr<CompilerInstance> Clang(new CompilerInstance());
    IntrusiveRefCntPtr<DiagnosticIDs> DiagID(new DiagnosticIDs());

    llvm::InitializeNativeTarget();
    llvm::InitializeNativeTargetAsmParser();

    IntrusiveRefCntPtr<DiagnosticOptions> DiagOpts(new DiagnosticOptions());

    TextDiagnosticBuffer *DiagsBuffer = new TextDiagnosticBuffer;

    DiagnosticsEngine Diags(DiagID, &*DiagOpts, DiagsBuffer);

    bool Success = CompilerInvocation::CreateFromArgs(
        Clang->getInvocation(),
        argv.data() + 1,
        argv.data() + argv.size(),
        Diags);

    Clang->createDiagnostics();

    install_fatal_error_handler(LLVMErrorHandler, &Clang->getDiagnostics());
    DiagsBuffer->FlushDiagnostics(Clang->getDiagnostics());

    if (Success) {
        Success = ExecuteCompilerInvocation(Clang.get());
        remove_fatal_error_handler();
        llvm::llvm_shutdown();
    }

    return !Success;
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
