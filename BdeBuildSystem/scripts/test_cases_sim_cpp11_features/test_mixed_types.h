// test_mixed_types.h                                                 -*-C++-*-
#ifndef INCLUDED_TEST_MIXED_TYPES
#define INCLUDED_TEST_MIXED_TYPES

#include <bsls_compilerfeatures.h>

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3

template <class T, class U, class... REST>
void threeOrMore(T&& first, U&& second, REST&&... rest) {
    process(std::forward<T>(first),
            std::forward<U>(second),
            std::forward<REST>(rest)...);
}

template <int N, class... TYPES>
class MixedParams {
  public:
    void method(const TYPES&... args);
};

template <int N, class... TYPES>
void MixedParams<N, TYPES...>::method(const TYPES&... args) {
    doMethod<N>(args...);
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
