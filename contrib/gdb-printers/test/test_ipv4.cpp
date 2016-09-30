#include <bsl_iostream.h>
#include <bteso_ipv4address.h>

using namespace BloombergLP;
int main()
{
    bteso_IPv4Address addr;

    bsl::cout << addr << "\n";

    bteso_IPv4Address addr2("192.168.100.1", 8080);

    bsl::cout << addr2 << "\n";

    std::cout << "Done\n";
}
