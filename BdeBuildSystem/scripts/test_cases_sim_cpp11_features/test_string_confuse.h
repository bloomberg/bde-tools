// test_string_confuse.h                                              -*-C++-*-
#ifndef INCLUDED_TEST_STRING_CONFUSE
#define INCLUDED_TEST_STRING_CONFUSE

#include <bsls_compilerfeatures.h>

// Edge case: String literals that might confuse the parser
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=2

template <class... ARGS>
void withStrings(ARGS&&... args) {
    const char *a = "template <class... T>";
    const char *b = "std::forward<X>(y)...";
    const char *c = "// this is not a comment";
    const char *d = "T&&";
    const char *e = "#if !BSLS";
    process(std::forward<ARGS>(args)...);
}

template <class T>
void escapedStrings(T&& val) {
    const char *s = "quotes: \"nested\" end";
    const char *t = "backslash: \\ end";
    doWork(std::forward<T>(val));
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
