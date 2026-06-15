// test_non_type_pack.h                                               -*-C++-*-
#ifndef INCLUDED_TEST_NON_TYPE_PACK
#define INCLUDED_TEST_NON_TYPE_PACK

#include <bsls_compilerfeatures.h>

// Test case from Perl: Non-type template parameter packs (int...)
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3

template <int... B, class... A>
void mixedNonTypeAndType(C<B...>* c, A&&... a) {
    D<A...> d(std::forward<A>(a)...);
    bar(sizeof...(A), c, &d);
}

template <int X, unsigned... V>
struct NonTypeStruct {
    typename mf<X>::type member();
};

template <int X, unsigned... V>
typename mf<X>::type NonTypeStruct<X, V...>::member() {
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
