void f1(int a[]);
void f2(int a[10]);
void f3(int []);
void f4(int [10]);
void f5(int (&a)[]);
void f6(int (&a)[10]);
void f7(int (&)[]);
void f8(int (&)[10]);

template <typename T> void t1(T a[]);
template <typename T> void t2(T a[10]);
template <typename T> void t3(T []);
template <typename T> void t4(T [10]);
template <typename T> void t5(T (&a)[]);
template <typename T> void t6(T (&a)[10]);
template <typename T> void t7(T (&)[]);
template <typename T> void t8(T (&)[10]);
