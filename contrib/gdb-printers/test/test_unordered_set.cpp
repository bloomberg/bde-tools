#include <bsl_iostream.h>
#include <bsl_string.h>
#include <bsl_unordered_set.h>

int main()
{
    bsl::unordered_set<int> si;
    si.insert(1);
    si.insert(2);
    si.insert(3);
    si.insert(4);
    si.insert(5);

    bsl::unordered_set<bsl::string> ss;
    ss.insert("one");
    ss.insert("two");
    ss.insert("three");

    struct SI {
        static void f(int n) { bsl::cout << n << "\n"; }
    };
    bsl::for_each(si.begin(), si.end(), &SI::f);

    struct SS {
        static void f(bsl::string s) { bsl::cout << s << "\n"; }
    };
    bsl::for_each(ss.begin(), ss.end(), &SS::f);

    std::cout << "Done\n";
}
