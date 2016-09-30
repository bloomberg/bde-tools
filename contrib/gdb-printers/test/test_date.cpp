#include <bdet_date.h>
#include <bsl_iostream.h>

using namespace BloombergLP;

int main()
{
    bdet_Date def;
    bdet_Date pre1752(1501, 8, 27);

    bdet_Date first(1970, 12, 20);

    bdet_Date leap1(2012, 2, 27);
    bdet_Date leap2(2012, 2, 28);
    bdet_Date leap3(2012, 3, 1);

    bsl::cout << def << "\n";
    bsl::cout << pre1752 << "\n";
    bsl::cout << first << "\n";
    bsl::cout << leap1 << "\n";
    bsl::cout << leap2 << "\n";
    bsl::cout << leap3 << "\n";

    std::cout << "Done\n";
}
