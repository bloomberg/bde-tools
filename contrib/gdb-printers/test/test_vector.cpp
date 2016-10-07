#include <bsl_iostream.h>
#include <bsl_string.h>
#include <bsl_vector.h>

int main()
{
    bsl::vector<int> vi(10, 5);

    bsl::vector<bsl::string> vs;
    vs.emplace_back("");
    vs.emplace_back("Hello there");
    vs.emplace_back("Goodbye");
    vs.emplace_back("");

    bsl::vector<bool> vb;
    vb.push_back(false);
    vb.push_back(true);

    struct SS {
        static void f(bsl::string s) { bsl::cout << s << "\n"; }
    };
    bsl::for_each(vs.begin(), vs.end(), &SS::f);

    struct SB {
        static void f(bool n) { bsl::cout << n << "\n"; }
    };
    bsl::for_each(vb.begin(), vb.end(), &SB::f);

    bsl::cout << "Done\n";
}
