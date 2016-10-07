#include <bdlt_date.h>
#include <bsl_iostream.h>

using namespace BloombergLP;

int main()
{
    bdlt::Date def;
    bdlt::Date pre1752(1501, 8, 27);

    bdlt::Date first(1970, 12, 20);

    bdlt::Date leap1(2012, 2, 27);
    bdlt::Date leap2(2012, 2, 28);
    bdlt::Date leap3(2012, 3, 1);

    bsl::cout << def << "\n";
    bsl::cout << pre1752 << "\n";
    bsl::cout << first << "\n";
    bsl::cout << leap1 << "\n";
    bsl::cout << leap2 << "\n";
    bsl::cout << leap3 << "\n";

    bsl::cout << "Done\n";
}
