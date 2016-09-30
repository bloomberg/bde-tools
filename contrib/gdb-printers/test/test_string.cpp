#include <bsl_iostream.h>
#include <bsl_string.h>

int main()
{
    bsl::string str = "This is a string";
    bsl::cout << str.size() << "\n";

    bsl::string max_short32(19, 'b');
    bsl::string min_large32(20, 'c');

    bsl::string max_short64(23, 'd');
    bsl::string min_large64(24, 'e');

    bsl::string large(100, 'a');
    bsl::cout << large.size() << "\n";

    return 0;
}
