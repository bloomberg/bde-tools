#include <xyzb_component.h>
#include <xyzc_component.h>

namespace xyzb {

void foo() {};
void bar() { return xyzc::foo(); }

}
