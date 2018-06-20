#include <bdet_datetime.h>
#include <bsl_iostream.h>

using namespace BloombergLP;

int main()
{
    bdlt::Datetime def;
    bdlt::Datetime pre1752(1501, 8, 27);

    bdlt::Datetime first(1970, 12, 20);

    bdlt::Datetime leap1(2012, 2, 27);
    bdlt::Datetime leap2(2012, 2, 28);
    bdlt::Datetime leap3(2012, 3, 1);

    bdlt::Datetime full(2016, 10, 7, 15, 52, 27, 99, 400);

    bsl::cout << def << "\n";
    bsl::cout << pre1752 << "\n";
    bsl::cout << first << "\n";
    bsl::cout << leap1 << "\n";
    bsl::cout << leap2 << "\n";
    bsl::cout << leap3 << "\n";
    bsl::cout << full << "\n";

    bsl::cout << "Done\n";
}
