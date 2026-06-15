// test_allocator_traits.h                                            -*-C++-*-
#ifndef INCLUDED_TEST_ALLOCATOR_TRAITS
#define INCLUDED_TEST_ALLOCATOR_TRAITS

#include <bsls_compilerfeatures.h>

// Test case from Perl: allocator_traits pattern with nested templates
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3

template <class ALLOCATOR_TYPE>
class allocator_traits {
  public:
    template <class ELEMENT_TYPE, class CTOR_ARG, class... CTOR_ARGS>
    static void construct(ALLOCATOR_TYPE&  allocator,
                          ELEMENT_TYPE    *elementAddr,
                          CTOR_ARG&&       ctorArg,
                          CTOR_ARGS&&...   ctorArgs);
};

template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG, class... CTOR_ARGS>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                                            CTOR_ARG&&       ctorArg,
                                            CTOR_ARGS&&...   ctorArgs)
{
    ::new (elementAddr) ELEMENT_TYPE(
        std::forward<CTOR_ARG>(ctorArg),
        std::forward<CTOR_ARGS>(ctorArgs)...);
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
