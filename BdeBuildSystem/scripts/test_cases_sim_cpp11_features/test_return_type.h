// test_return_type.h                                                 -*-C++-*-
#ifndef INCLUDED_TEST_RETURN_TYPE
#define INCLUDED_TEST_RETURN_TYPE

#include <bsls_compilerfeatures.h>

// Edge case: Variadic templates with various return types
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=2

template <class... ARGS>
int returnsInt(ARGS&&... args) {
    return process(std::forward<ARGS>(args)...);
}

template <class R, class... ARGS>
R returnsR(ARGS&&... args) {
    return static_cast<R>(process(std::forward<ARGS>(args)...));
}

template <class... ARGS>
auto trailingReturn(ARGS&&... args) -> decltype(process(args...)) {
    return process(std::forward<ARGS>(args)...);
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
