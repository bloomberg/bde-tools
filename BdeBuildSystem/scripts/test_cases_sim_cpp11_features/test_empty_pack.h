// test_empty_pack.h                                                  -*-C++-*-
#ifndef INCLUDED_TEST_EMPTY_PACK
#define INCLUDED_TEST_EMPTY_PACK

#include <bsls_compilerfeatures.h>

// Edge case: Test handling of empty variadic packs (0 arguments)
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=2

template <class... ARGS>
void emptyPackAllowed(ARGS&&... args) {
    process(std::forward<ARGS>(args)...);
}

template <class T, class... ARGS>
void atLeastOne(T&& first, ARGS&&... rest) {
    handle(std::forward<T>(first), std::forward<ARGS>(rest)...);
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
