#include <bsls_atomic.h>
#include <bsl_iostream.h>

using namespace BloombergLP;

int main()
{
    bsls::AtomicInt aint;
    aint = 10;
    bsl::cout << aint << "\n";

    bsls::AtomicInt64 aint64;
    aint64 = 64;
    bsl::cout << aint64 << "\n";

    bsls::AtomicPointer<int> aptr;
    aptr = 0;
    bsl::cout << aptr << "\n";

    bsl::cout << "Done\n";
}
