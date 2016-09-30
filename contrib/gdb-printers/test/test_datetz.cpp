#include <bdet_datetz.h>
#include <bsl_iostream.h>

using namespace BloombergLP;

int main()
{
    bdet_Date   date(2015, 1, 15);
    bdet_DateTz def;

    bsl::cout << "Date is " << def << "\n";

    def.setDateTz(date, 0);
    bsl::cout << "Date is " << def << "\n";

    def.setDateTz(date, 1);
    bsl::cout << "Date is " << def << "\n";

    def.setDateTz(date, -5);
    bsl::cout << "Date is " << def << "\n";

    std::cout << "Done\n";
}
