// csabase_clang.h                                                    -*-C++-*-
#ifndef INCLUDED_CSABASE_CLANG
#define INCLUDED_CSABASE_CLANG

#include <clang/Basic/SourceLocation.h>
#include <llvm/ADT/Hashing.h>
#include <llvm/ADT/StringRef.h>
#include <tuple>
#include <utility>

namespace std
{

template <typename A, typename B>
struct hash<pair<A, B>>
{
    size_t operator()(const pair<A, B>& p) const
    {
        return llvm::hash_combine(hash<A>()(p.first), hash<B>()(p.second));
    }
};

template <typename A, typename B, typename C>
struct hash<tuple<A, B, C>>
{
    size_t operator()(const tuple<A, B, C>& t) const
    {
        return llvm::hash_combine(
            hash<A>()(get<0>(t)), hash<B>()(get<1>(t)), hash<C>()(get<2>(t)));
    }
};

template <>
struct hash<clang::SourceLocation>
{
    size_t operator()(const clang::SourceLocation& sl) const
    {
        return sl.getRawEncoding();
    }
};

template <>
struct hash<clang::SourceRange>
{
    size_t operator()(const clang::SourceRange& sr) const
    {
        return llvm::hash_combine(
            sr.getBegin().getRawEncoding(), sr.getEnd().getRawEncoding());
    }
};

template <>
struct hash<llvm::StringRef> {
    size_t operator()(const llvm::StringRef& sr) const
    {
        return llvm::hash_value(sr);
    }
};

template <>
struct hash<clang::FileID> {
    size_t operator()(const clang::FileID& fid) const
    {
        return fid.getHashValue();
    }
};

}

namespace clang
{

inline
bool operator<(const clang::SourceRange& a, const clang::SourceRange& b)
{
    if (a.getBegin() < b.getBegin()) return true;
    if (b.getBegin() < a.getBegin()) return false;

    if (a.getEnd()   < b.getEnd()  ) return true;
//  if (b.getEnd()   < a.getEnd()  ) return false;
    return false;
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
