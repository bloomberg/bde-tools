#include <bsl_iostream.h>
#include <bsl_string.h>
#include <bslstl_stringref.h>

using namespace BloombergLP;

int main()
{
    bslstl::StringRef defref;
    bsl::cout << defref << "\n";

    bsl::string str = "This is a string";
    bslstl::StringRef strref(str.begin(), str.end());
    bsl::cout << strref << "\n";

    bsl::cout << "Done\n";
}
