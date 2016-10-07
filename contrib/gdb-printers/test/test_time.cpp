#include <bdlt_time.h>
#include <bsl_iostream.h>

using namespace BloombergLP;

int main()
{
    bdlt::Time def;
    bdlt::Time midnight(0, 0, 0, 0);
    bdlt::Time noon(12, 0, 0, 0);

    bdlt::Time random(10, 20, 30, 444);

    bsl::cout << def << "\n";
    bsl::cout << midnight << "\n";
    bsl::cout << noon << "\n";
    bsl::cout << random << "\n";

    bsl::cout << "Done\n";
}
