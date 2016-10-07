#include <bdlt_timetz.h>
#include <bsl_iostream.h>

using namespace BloombergLP;

int main()
{
    bdlt::Time def;
    bdlt::TimeTz deftz(def, +1000);
    bdlt::Time midnight(0, 0, 0, 0);
    bdlt::TimeTz midnighttz(midnight, -1200);
    bdlt::Time noon(12, 0, 0, 0);
    bdlt::TimeTz noontz(noon, 0);

    bdlt::Time random(10, 20, 30, 444);
    bdlt::TimeTz randomtz(random, 300);

    bsl::cout << deftz << "\n";
    bsl::cout << midnighttz << "\n";
    bsl::cout << noontz << "\n";
    bsl::cout << randomtz << "\n";

    bsl::cout << "Done\n";
}
