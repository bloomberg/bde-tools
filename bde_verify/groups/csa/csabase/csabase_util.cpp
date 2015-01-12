// csabase_util.cpp                                                   -*-C++-*-

#include <csabase_util.h>
#include <csabase_debug.h>
#include <clang/Basic/SourceManager.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/Support/Regex.h>
#include <cctype>

using namespace clang;
using namespace csabase;

std::pair<size_t, size_t>
csabase::mid_mismatch(const std::string &have, const std::string &want)
{
    std::pair<size_t, size_t> result(0, 0);
    while (   result.first < have.size()
           && result.first < want.size()
           && have[result.first] == want[result.first]) {
        ++result.first;
    }
    while (   result.second < have.size()
           && result.second < want.size()
           && have.size() > result.first + result.second
           && want.size() > result.first + result.second
           && have[have.size() - result.second - 1] ==
              want[want.size() - result.second - 1]) {
        ++result.second;
    }
    return result;
}

std::pair<size_t, size_t>
csabase::mid_match(const std::string &have, const std::string &want)
{
    std::pair<size_t, size_t> result(have.find(want), have.npos);
    if (result.first != have.npos) {
        result.second = have.size() - want.size() - result.first;
    }
    return result;
}

static llvm::Regex between_comments(
    "^[[:blank:]]*[[:space:]]?[[:blank:]]*$",
    llvm::Regex::NoFlags);

bool csabase::areConsecutive(clang::SourceManager &manager,
                             clang::SourceRange first,
                             clang::SourceRange second)
{
    clang::FileID fidf = manager.getFileID(first.getEnd());
    clang::FileID fids = manager.getFileID(second.getBegin());
    size_t colf = manager.getPresumedColumnNumber(first.getBegin());
    size_t cols = manager.getPresumedColumnNumber(second.getBegin());
    size_t offf = manager.getFileOffset(first.getEnd());
    size_t offs = manager.getFileOffset(second.getBegin());

    return fidf == fids && colf == cols && offf <= offs &&
           between_comments.match(
               manager.getBufferData(fidf).substr(offf, offs - offf));
}

std::string csabase::to_lower(std::string s)
{
    return llvm::StringRef(s).lower();
}

bool csabase::contains_word(const std::string &have, const std::string &want)
{
    std::pair<size_t, size_t> m = mid_match(have, want);
    if (m.first == have.npos) {
        return false;
    }
    if (m.first > 0) {
        char c = have[m.first - 1];
        if (std::isalnum(c) || c == '_') {
            return false;
        }
    }
    if (m.second > 0) {
        char c = have[have.size() - m.second];
        if (std::isalnum(c) || c == '_') {
            return false;
        }
    }
    return true;
}

csabase::OnMatch<UseLambda, &UseLambda::NotFunction>::OnMatch(
    const std::function<void(const clang::ast_matchers::BoundNodes &)> &fun)
    : function_(fun)
{
}

void csabase::OnMatch<UseLambda, &UseLambda::NotFunction>::run(
    const clang::ast_matchers::MatchFinder::MatchResult &result)
{
    function_(result.Nodes);
}

SourceRange csabase::getOffsetRange(SourceLocation loc, int offset, int size)
{
    return SourceRange(loc.getLocWithOffset(offset),
                       loc.getLocWithOffset(offset + size));
}

SourceRange csabase::getOffsetRange(SourceRange range, int offset, int size)
{
    return SourceRange(range.getBegin().getLocWithOffset(offset),
                       range.getBegin().getLocWithOffset(offset + size));
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
