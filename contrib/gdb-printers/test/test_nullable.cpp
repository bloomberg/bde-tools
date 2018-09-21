#include <bdeut_nullablevalue.h>
#include <bsl_iostream.h>
#include <bsl_string.h>

using namespace BloombergLP;
int main()
{
    bdeut_NullableValue<int> vi;
    bdeut_NullableValue<int> *volatile pvi = &vi;
    *pvi = 0xFF775511;

    bdeut_NullableValue<bsl::string> vs;
    vs = "This is the string value";

    bsl::cout << vi.value() << '|' << vs.value() << "\n";

    bsl::cout << "Done\n";
}
