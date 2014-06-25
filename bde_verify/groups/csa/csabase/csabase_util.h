// csabase_util.h                                                     -*-C++-*-

#ifndef INCLUDED_CSABASE_UTIL
#define INCLUDED_CSABASE_UTIL

#include <clang/ASTMatchers/ASTMatchFinder.h>
#include <clang/ASTMatchers/ASTMatchers.h>
#include <clang/Basic/SourceLocation.h>
#include <stddef.h>
#include <functional>
#include <string>
#include <utility>

namespace clang { class SourceManager; }

namespace csabase
{
std::pair<size_t, size_t>
mid_mismatch(const std::string &have, const std::string &want);
    // Return a pair of values '(a,b)' such that 'a' is the maximum length of a
    // common prefix of the specified 'have' and 'want' and 'b' is the maximum
    // length of a common suffix of 'have.substr(a)' and 'want.substr(a)'.

std::pair<size_t, size_t>
mid_match(const std::string &have, const std::string &want);
    // Return a pair of values '(a,b)' such that 'a' is the count of characters
    // in the specified 'have' before the first appearance of the specified
    // 'want' and 'b' is the count of characters in 'have' after the first
    // appearance of 'want'.  If 'want' is not in 'have', return a pair of
    // 'npos' instead.

bool areConsecutive(clang::SourceManager& manager,
                    clang::SourceRange    first,
                    clang::SourceRange    second);
    // Return 'true' iff the specified 'first' range is immediately followed by
    // the specified 'second' range, with only whitespace in between, and the
    // two begin at the same column.  (This is used to paste consecutive '//'
    // comments into single blocks.)

std::string to_lower(std::string s);
    // Return a copy of the specified 's' with all letters in lower case.

struct UseLambda {
    void NotFunction(const clang::ast_matchers::BoundNodes &);
};

template <class Class = UseLambda,
          void (Class::*Method)(const clang::ast_matchers::BoundNodes &) =
              &UseLambda::NotFunction>
class OnMatch : public clang::ast_matchers::MatchFinder::MatchCallback
    // This class template acts as an intermediary to forward AST match
    // callbacks to the specified 'Method' of the specified 'Class'.
{
  public:
    OnMatch(Class *object);
        // Create an 'OnMatch' object, storing the specified 'object' pointer
        // for use in the callback.

    void run(const clang::ast_matchers::MatchFinder::MatchResult &result);
        // Invoke the 'Method' of the 'object_', passing the 'BoundNodes' from
        // the specified 'result' as an argument.

  private:
    Class *object_;
};

template <class Class,
          void (Class::*Method)(const clang::ast_matchers::BoundNodes &)>
OnMatch<Class, Method>::OnMatch(Class *object)
: object_(object)
{
}

template <class Class,
          void (Class::*Method)(const clang::ast_matchers::BoundNodes &)>
void OnMatch<Class, Method>::run(
    const clang::ast_matchers::MatchFinder::MatchResult &result)
{
    (object_->*Method)(result.Nodes);
}

template <>
class OnMatch<UseLambda, &UseLambda::NotFunction> :
    public clang::ast_matchers::MatchFinder::MatchCallback
    // This class template acts as an intermediary to forward AST match
    // callbacks to the specified lambda.
{
  public:
    OnMatch(const std::function<
        void(const clang::ast_matchers::BoundNodes &)> &fun);
        // Create an 'OnMatch' object, storing the specified 'function'

    void run(const clang::ast_matchers::MatchFinder::MatchResult &result);
        // Invoke the 'function_', passing the 'BoundNodes' from the specified
        // 'result' as an argument.

  private:
    std::function<void(const clang::ast_matchers::BoundNodes &)> function_;
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
