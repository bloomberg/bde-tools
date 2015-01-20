#include <bsl_memory.h>
#include <bslma_allocator.h>
#include <bslmf_integralconstant.h>
#include <bslma_usesbslmaallocator.h>
using namespace BloombergLP;
template <class T> struct B {             B(bslma::Allocator* alloc = 0) { } };
                   struct C {             C(bslma::Allocator* alloc = 0) { } };
template <class T> struct D {             D(bslma::Allocator* alloc = 0) { } };
                   struct E {             E(bslma::Allocator* alloc = 0) { } };
struct A { E e; D<int> d; C c; B<int> b;  A(bslma::Allocator* alloc = 0) { } };
namespace BloombergLP { namespace bslma {
template <>        struct UsesBslmaAllocator<E>    : bsl::true_type { };
template <class T> struct UsesBslmaAllocator<D<T>> : bsl::true_type { };
template <>        struct UsesBslmaAllocator<C>    : bsl::false_type { };
template <class T> struct UsesBslmaAllocator<B<T>> : bsl::false_type { };
template <>        struct UsesBslmaAllocator<A>    : bsl::true_type  { };
} }
int main() { A a; }
