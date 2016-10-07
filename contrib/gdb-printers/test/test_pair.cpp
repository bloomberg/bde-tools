#include <bsl_iostream.h>
#include <bsl_utility.h>

int main() {
    bsl::pair<int,double> pii(0,1.5);
    bsl::pair<int,bsl::string> pis(1,"There");
    bsl::pair<bsl::string,int> psi("Hi", 2);
    bsl::pair<bsl::string,bsl::string> pss("Hi", "there");

    bsl::cout << pii.first << "\n";

    bsl::cout << "Done\n";
}
