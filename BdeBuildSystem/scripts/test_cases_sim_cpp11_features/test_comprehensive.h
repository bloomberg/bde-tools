// test_comprehensive.h                                              -*-C++-*-
// Combined test file for CLI testing - includes cases from all test files
#ifndef INCLUDED_TEST_COMPREHENSIVE
#define INCLUDED_TEST_COMPREHENSIVE

#include <bsls_compilerfeatures.h>

// ============================================================================
// SECTION 1: Variadic Functions (from test_variadic_function.h)
// ============================================================================

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=5

template <class... ARGS>
void simpleVariadic(ARGS&&... args) {
    process(std::forward<ARGS>(args)...);
}

template <class T, class... REST>
void mixedVariadic(T&& first, REST&&... rest) {
    handle(std::forward<T>(first), std::forward<REST>(rest)...);
}

#endif

// ============================================================================
// SECTION 2: Variadic Classes (from test_variadic_class.h)
// ============================================================================

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES

template <class... TYPES>
class VariadicClass {
  public:
    void process(TYPES&&... args) {
        handle(std::forward<TYPES>(args)...);
    }
};

template <class... TYPES>
struct VariadicStruct {
    static void method(const TYPES&... values);
};

#endif

// ============================================================================
// SECTION 3: Forwarding (from test_forwarding.h)
// ============================================================================

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES

template <class T>
void forwardOne(T&& value) {
    process(std::forward<T>(value));
}

template <class T, class U>
void forwardTwo(T&& first, U&& second) {
    process(std::forward<T>(first), std::forward<U>(second));
}

#endif

// ============================================================================
// SECTION 4: Nested Classes (from test_nested_class.h)
// ============================================================================

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $local-var-args=3

template <class... OUTER>
class OuterVariadic {
  public:
    template <class... INNER>
    class NestedClass {
      public:
        void method(OUTER&&... o, INNER&&... i);
    };

    template <class U>
    void memberTemplate(U&& value) {
        process(std::forward<U>(value));
    }
};

#endif

// ============================================================================
// SECTION 5: sizeof... (from test_sizeof.h)
// ============================================================================

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES

template <class... ARGS>
void useSizeof(ARGS&&... args) {
    const size_t count = sizeof...(ARGS);
    if (sizeof...(args) > 0) {
        process(count, std::forward<ARGS>(args)...);
    }
}

#endif

// ============================================================================
// SECTION 6: Constructors (from test_constructor.h)
// ============================================================================

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES

template <class... ARGS>
class ClassWithVariadicCtor {
  public:
    explicit ClassWithVariadicCtor(ARGS&&... args) {
        init(std::forward<ARGS>(args)...);
    }
};

#endif

// ============================================================================
// SECTION 7: Const References (from test_const_ref.h)
// ============================================================================

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES

template <class... ARGS>
void constRefVariadic(const ARGS&... args) {
    process(args...);
}

#endif

// ============================================================================
// SECTION 8: Non-type Template Parameters (from test_non_type_pack.h)
// ============================================================================

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES

template <int... VALUES>
struct IntPack {
    static constexpr int sum();
};

template <class T, T... VALUES>
struct TypedPack {
    static void process();
};

#endif

// ============================================================================
// SECTION 9: Return Types (from test_return_type.h)
// ============================================================================

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES

template <class... ARGS>
int variadicReturningInt(ARGS&&... args) {
    return process(std::forward<ARGS>(args)...);
}

template <class... ARGS>
auto variadicReturningAuto(ARGS&&... args) -> decltype(process(args...)) {
    return process(std::forward<ARGS>(args)...);
}

#endif

// ============================================================================
// SECTION 10: Operators (from test_operator.h)
// ============================================================================

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES

template <class... ARGS>
class ClassWithOperator {
  public:
    void operator()(ARGS&&... args) {
        invoke(std::forward<ARGS>(args)...);
    }
};

#endif

#endif // INCLUDED_TEST_COMPREHENSIVE

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
