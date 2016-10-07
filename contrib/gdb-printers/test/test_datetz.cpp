#include <bdlt_datetz.h>
#include <bsl_iostream.h>

using namespace BloombergLP;

int main()
{
    bdlt::Date   date(2015, 1, 15);
    bdlt::DateTz def;

    bsl::cout << "Date is " << def << "\n";

    def.setDateTz(date, 0);
    bsl::cout << "Date is " << def << "\n";

    def.setDateTz(date, 1);
    bsl::cout << "Date is " << def << "\n";

    def.setDateTz(date, -5);
    bsl::cout << "Date is " << def << "\n";

    bsl::cout << "Done\n";
}
