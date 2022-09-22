#include <m_xyzwithlib_component.h>
#include <testlib.h>

#include <iostream>
#include <stdlib.h>

int main(int argc, char *argv[])
{
    const int test = argc > 1 ? atoi(argv[1]) : 0;

    switch (test) {
      case 0:
      case 1:
        xyzwithlib();
        testlib();
        return 0;
      default:
        return -1;
    };

    return 0;
}
