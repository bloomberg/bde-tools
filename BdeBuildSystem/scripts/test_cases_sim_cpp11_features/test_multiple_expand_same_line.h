// test_multiple_expand_same_line.h                                   -*-C++-*-
#ifndef INCLUDED_TEST_MULTIPLE_EXPAND_SAME_LINE
#define INCLUDED_TEST_MULTIPLE_EXPAND_SAME_LINE

#include <bsls_compilerfeatures.h>

// Test case from Perl: Multiple identical expansions on same line
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3

template <class... A>
void multipleOnSameLine(A&&... a) {
    f(std::forward<A>(a)...); g(std::forward<A>(a)...);
}

template <class... T>
void twoForwardCalls(T&&... t) {
    first(std::forward<T>(t)...); second(std::forward<T>(t)...); third(std::forward<T>(t)...);
}

#endif

#endif

// ----------------------------------------------------------------------------
// Copyright 2020 Bloomberg Finance L.P.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// ----------------------------- END-OF-FILE ----------------------------------
