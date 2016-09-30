#include <bsl_iostream.h>
#include <bsl_memory.h>

int main()
{
    bsl::shared_ptr<int> p1;

    bsl::shared_ptr<int> p2(new int(5));

    bsl::weak_ptr<int> w2(p2);

    bsl::weak_ptr<int> w22(w2);

    bsl::shared_ptr<int> p22(p2);

    return 0;
}
