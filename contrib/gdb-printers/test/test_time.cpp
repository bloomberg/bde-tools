#include <bdet_time.h>
#include <bsl_iostream.h>

using namespace BloombergLP;

int main()
{
    bdet_Time def;
    bdet_Time midnight(0, 0, 0, 0);
    bdet_Time noon(12, 0, 0, 0);

    bdet_Time random(10, 20, 30, 444);

    bsl::cout << def << "\n";
    bsl::cout << midnight << "\n";
    bsl::cout << noon << "\n";
    bsl::cout << random << "\n";

    return 0;
}
