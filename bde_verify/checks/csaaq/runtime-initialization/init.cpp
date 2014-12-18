extern int function();
struct C { C(); };
extern int *pointer;
extern int integer;

int extern_should_be_static = 3;
int extern_should_be_runtime_call = function();
C extern_should_be_runtime_constructed;
int extern_should_be_runtime_expression = *pointer;
int extern_should_be_static_expression = (9 + 7) * (9 - 7);
int &extern_should_be_static_reference = integer;

namespace {
int extern_should_be_static = 3;
int extern_should_be_runtime_call = function();
C extern_should_be_runtime_constructed;
int extern_should_be_runtime_expression = *pointer;
int extern_should_be_static_expression = (9 + 7) * (9 - 7);
int &extern_should_be_static_reference = integer;
}

namespace N {
int extern_should_be_static = 3;
int extern_should_be_runtime_call = function();
C extern_should_be_runtime_constructed;
int extern_should_be_runtime_expression = *pointer;
int extern_should_be_static_expression = (9 + 7) * (9 - 7);
int &extern_should_be_static_reference = integer;
}

static int static_should_be_static = 3;
static int static_should_be_runtime_call = function();
static C static_should_be_runtime_constructed;
static int static_should_be_runtime_expression = *pointer;
static int static_should_be_static_expression = (9 + 7) * (9 - 7);
static int &static_should_be_static_reference = integer;

void g()
{
    static int should_be_static = 3;
    static int should_be_runtime_call = function();
    static C should_be_runtime_constructed;
    static int should_be_runtime_expression = *pointer;
    static int should_be_static_expression = (9 + 7) * (9 - 7);
    static int &static_should_be_static_reference = integer;
}

struct D
{
    static int should_be_static;
    static int should_be_runtime_call;
    static C should_be_runtime_constructed;
    static int should_be_runtime_expression;
    static int should_be_static_expression;
    static int &static_should_be_static_reference;
};

int D::should_be_static = 3;
int D::should_be_runtime_call = function();
C D::should_be_runtime_constructed;
int D::should_be_runtime_expression = *pointer;
int D::should_be_static_expression = (9 + 7) * (9 - 7);
int &D::static_should_be_static_reference = integer;

template <class T>
struct E
{
    static int should_be_static;
    static int should_be_runtime_call;
    static C should_be_runtime_constructed;
    static int should_be_runtime_expression;
    static int should_be_static_expression;
    static int &static_should_be_static_reference;
};

template <class T> int E<T>::should_be_static = 3;
template <class T> int E<T>::should_be_runtime_call = function();
template <class T> C E<T>::should_be_runtime_constructed;
template <class T> int E<T>::should_be_runtime_expression = *pointer;
template <class T> int E<T>::should_be_static_expression = (9 + 7) * (9 - 7);
template <class T> int &E<T>::static_should_be_static_reference = integer;
