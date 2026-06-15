// test_pointer_array.h                                               -*-C++-*-
#ifndef INCLUDED_TEST_POINTER_ARRAY
#define INCLUDED_TEST_POINTER_ARRAY

#include <bsls_compilerfeatures.h>

// Edge case: Variadic templates with pointers and arrays
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=2

template <class... TYPES>
class WithPointers {
    char d_data[64];
  public:
    void method(TYPES*... ptrs);
    void constPtrs(const TYPES*... ptrs);
};

template <class... TYPES>
void WithPointers<TYPES...>::method(TYPES*... ptrs) {
    process(ptrs...);
}

template <class... TYPES>
void WithPointers<TYPES...>::constPtrs(const TYPES*... ptrs) {
    process(ptrs...);
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
