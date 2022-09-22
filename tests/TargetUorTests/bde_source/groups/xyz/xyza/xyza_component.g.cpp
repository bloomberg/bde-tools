#include <xyza_component.h>
#include <testlib.h>

#include <string.h>
#include <iostream>

int main(int argc, char** argv)
{
  for (int i = 1; i < argc; ++i) {
    if (0 == strcmp(argv[i], "--gtest_list_tests")) {
      std::cout << "xyza_component." << std::endl
                << "  test1\n" << std::endl;
      return 0;
    }
    else if (0 == strcmp(argv[i], "--gtest_filter=xyza_component.test1")) {
      xyza();
      testlib();
      return 0;
    }
  }

  return 1;
}
