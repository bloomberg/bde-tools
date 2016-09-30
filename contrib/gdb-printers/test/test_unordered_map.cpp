#include <bsl_iostream.h>
#include <bsl_string.h>
#include <bsl_unordered_map.h>

int main()
{
    bsl::unordered_map<int, short> mii;
    mii[0] = 0;
    mii.erase(0);
    mii[0] = 1;
    mii[1] = 10;
    mii[2] = 20;

    bsl::unordered_map<int, bsl::string> mis;
    mis[0] = "zero";
    mis[1] = "ten";
    mis[2] = "twenty";

    bsl::unordered_map<int, int> single;
    single[100] = 0;

    bsl::cout << mii[0] << " " << mii[1] << " " << mii[2] << "\n";
    bsl::cout << mis[0] << " " << mis[1] << " " << mis[2] << "\n";
    bsl::cout << single[100] << "\n";

    return 0;
}
