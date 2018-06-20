#include <bsl_iostream.h>
#include <bsl_map.h>
#include <bsl_string.h>

int main()
{
    bsl::map<int, short> mii;
    mii[0] = 0;
    mii.erase(0);
    mii[0] = 1;
    mii[1] = 10;
    mii[2] = 20;

    bsl::map<int, bsl::string> mis;
    mis[0] = "zero";
    mis[1] = "ten";
    mis[2] = "twenty";

    bsl::map<int, int> single;
    single[100] = 0;

    bsl::cout << mii[0] << " " << mii[1] << " " << mii[2] << "\n";
    bsl::cout << mis[0] << " " << mis[1] << " " << mis[2] << "\n";
    bsl::cout << single[100] << "\n";

    bsl::cout << "Done\n";
}
