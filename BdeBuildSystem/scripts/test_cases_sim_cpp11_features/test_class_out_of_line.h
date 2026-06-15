// test_class_out_of_line.h                                           -*-C++-*-
#ifndef INCLUDED_TEST_CLASS_OUT_OF_LINE
#define INCLUDED_TEST_CLASS_OUT_OF_LINE

#include <bsls_compilerfeatures.h>

// Test case from Perl: Variadic class with out-of-line member definitions
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3

template <int X, class... T>
class C {
  public:
    typename mf<X>::type member(const T&... z);

    template <class U> void member2(U&& v);
};

template <int X, class... T>
typename mf<X>::type C<X, T...>::member(const T&... z) {
}

template <int X, class... T>
    template <class U>
void C<X, T...>::member2(U&& v) {
    q(std::forward<U>(v));
}

template <int X, unsigned... V>
struct D {
    typename mf<X>::type member();
};

template <int X, unsigned... V>
typename mf<X>::type D<X, V...>::member() {
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
