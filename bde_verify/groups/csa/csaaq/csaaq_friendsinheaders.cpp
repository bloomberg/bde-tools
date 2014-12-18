// csaaq_friendsinheaders.cpp                                         -*-C++-*-

#include <csabase_analyser.h>
#include <csabase_clang.h>
#include <csabase_config.h>
#include <csabase_debug.h>
#include <csabase_registercheck.h>
#include <csabase_report.h>
#include <csabase_visitor.h>
#include <map>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("friends-in-headers");

// ----------------------------------------------------------------------------

namespace
{

struct data
    // Data attached to analyzer for this check.
{
    std::map<SourceLocation, const FriendDecl *> d_friends;
};

struct report : Report<data>
{
    using Report<data>::Report;

    bool isDefinition(const Decl *decl);

    const NamedDecl *friendOf(const FriendDecl *fd);

    void operator()(const CXXRecordDecl *decl);

    bool isOther(const Decl *decl, const FriendDecl *fd, FileID fid);

    void operator()();
};

const NamedDecl *report::friendOf(const FriendDecl *fd)
{
    NamedDecl *decl = fd->getFriendDecl();
    if (!decl) {
        if (TypeSourceInfo *type = fd->getFriendType()) {
            decl = type->getType()->getAsCXXRecordDecl();
        }
    }
    return decl;
}

bool report::isDefinition(const Decl *decl)
{
    if (!decl) {
        return false;
    }
    if (auto d = llvm::dyn_cast<FunctionDecl>(decl)) {
        return d->isThisDeclarationADefinition();
    }
    if (auto d = llvm::dyn_cast<FunctionTemplateDecl>(decl)) {
        return d->isThisDeclarationADefinition();
    }
    if (auto d = llvm::dyn_cast<ClassTemplateDecl>(decl)) {
        return d->isThisDeclarationADefinition();
    }
    if (auto d = llvm::dyn_cast<VarDecl>(decl)) {
        return d->isThisDeclarationADefinition();
    }
    return false;
}

void report::operator()(const CXXRecordDecl *decl)
{
    if (decl->hasDefinition()) {
        auto fb = decl->friend_begin();
        auto fe = decl->friend_end();
        bool t = decl->getDescribedClassTemplate();
        for (; fb != fe; ++fb) {
            SourceLocation sl = (*fb)->getLocation();
            if ((!t && !d.d_friends.count(sl)) ||
                isDefinition(friendOf(*fb))) {
                d.d_friends[sl] = *fb;
            }
        }
    }
}

bool report::isOther(const Decl *decl, const FriendDecl *fd, FileID fid)
{
    SourceLocation dl = decl->getLocEnd();
    SourceLocation fl = fd->getLocEnd();
    return dl.isMacroID() ||
           (isDefinition(decl) && dl == fl) ||
           (m.getFileID(dl) == fid && dl != fl);
}

void report::operator()()
{
    std::set<const Decl *> done;
    for (const auto &p : d.d_friends) {
        const auto &f = p.second;
        SourceLocation sl = f->getLocation();
        if (sl.isMacroID() || !a.is_header(m.getFilename(sl))) {
            continue;
        }
        const Decl *decl = friendOf(f);
        if (!decl || done.count(decl)) {
            continue;
        }
        FileID fid = m.getFileID(sl);
        bool found = false;
        auto rb = decl->redecls_begin();
        auto re = decl->redecls_end();
        for (; !found && rb != re; ++rb) {
            found = done.count(*rb) || isOther(*rb, f, fid);
            done.insert(*rb);
        }
        if (!found) {
            a.report(f, check_name, "AQP01",
                     "Entities granted friendship must be declared in the "
                     "same header");
        }
    }
}

void subscribe(Analyser& analyser, Visitor& visitor, PPObserver& observer)
    // Hook up the callback functions.
{
    visitor.onCXXRecordDecl        += report(analyser);
    analyser.onTranslationUnitDone += report(analyser);
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
