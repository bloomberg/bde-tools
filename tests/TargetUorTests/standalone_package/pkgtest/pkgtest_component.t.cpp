#include <pkgtest_component.h>
#include <support.h>

#include <bsl_cstdlib.h>

using namespace bsl;

namespace {
    int testStatus = 0;
}

int main(int argc, char *argv[])
{
    int test = argc > 1 ? atoi(argv[1]) : 0;
    int verbose = argc > 2;
    int veryVerbose = argc > 3;
    int veryVeryVerbose = argc > 4;

    switch (test) {
        case 0: {
            support_foo();
        } break;
        default: {
            testStatus = -1;
        } break;
    }

    return testStatus;
}
