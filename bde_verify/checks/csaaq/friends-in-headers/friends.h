void c_function_declared_before();
void c_function_defined_before() { }
class c_class_declared_before;
class c_class_defined_before { };
template <class T> void c_function_template_declared_before(T);
template <class T> void c_function_template_defined_before(T) { }
template <class T> class c_class_template_declared_before;
template <class T> class c_class_template_defined_before { };

class c
{
    friend void c_function_undeclared();
    friend void c_function_declared_before();
    friend void c_function_declared_after();
    friend void c_function_declared_in_cpp();
    friend void c_function_defined_here() { }
    friend void c_function_defined_before();
    friend void c_function_defined_after();
    friend void c_function_defined_in_cpp();

    class c_class_defined_in_class_before { };

    friend class c_class_undeclared;
    friend class c_class_declared_before;
    friend class c_class_declared_after;
    friend class c_class_declared_in_cpp;
    friend class c_class_defined_in_class_before;
    friend class c_class_defined_in_class_after;
    friend class c_class_defined_before;
    friend class c_class_defined_after;
    friend class c_class_defined_in_cpp;

    class c_class_defined_in_class_after { };

    template <class T> friend void c_function_template_undeclared(T);
    template <class T> friend void c_function_template_declared_before(T);
    template <class T> friend void c_function_template_declared_after(T);
    template <class T> friend void c_function_template_declared_in_cpp(T);
    template <class T> friend void c_function_template_defined_here(T) { }
    template <class T> friend void c_function_template_defined_before(T);
    template <class T> friend void c_function_template_defined_after(T);
    template <class T> friend void c_function_template_defined_in_cpp(T);

    template <class T> class c_class_template_defined_in_class_before { };

    template <class T> friend class c_class_template_undeclared;
    template <class T> friend class c_class_template_declared_before;
    template <class T> friend class c_class_template_declared_after;
    template <class T> friend class c_class_template_declared_in_cpp;
    template <class T> friend class c_class_template_defined_in_class_before;
    template <class T> friend class c_class_template_defined_in_class_after;
    template <class T> friend class c_class_template_defined_before;
    template <class T> friend class c_class_template_defined_after;
    template <class T> friend class c_class_template_defined_in_cpp;

    template <class T> class c_class_template_defined_in_class_after { };
};

void c_function_declared_after();
void c_function_defined_after() { }
class c_class_declared_after;
class c_class_defined_after { };
template <class T> void c_function_template_declared_after(T);
template <class T> void c_function_template_defined_after(T) { }
template <class T> class c_class_template_declared_after;
template <class T> class c_class_template_defined_after { };

void u_function_declared_before();
void u_function_defined_before() { }
class u_class_declared_before;
class u_class_defined_before { };
template <class T> void u_function_template_declared_before(T);
template <class T> void u_function_template_defined_before(T) { }
template <class T> class u_class_template_declared_before;
template <class T> class u_class_template_defined_before { };

template <class C>
class u
{
    friend void u_function_undeclared();
    friend void u_function_declared_before();
    friend void u_function_declared_after();
    friend void u_function_declared_in_cpp();
    friend void u_function_defined_here() { }
    friend void u_function_defined_before();
    friend void u_function_defined_after();
    friend void u_function_defined_in_cpp();

    class u_class_defined_in_class_before { };

    friend class u_class_undeclared;
    friend class u_class_declared_before;
    friend class u_class_declared_after;
    friend class u_class_declared_in_cpp;
    friend class u_class_defined_in_class_before;
    friend class u_class_defined_in_class_after;
    friend class u_class_defined_before;
    friend class u_class_defined_after;
    friend class u_class_defined_in_cpp;

    class u_class_defined_in_class_after { };

    template <class T> friend void u_function_template_undeclared(T);
    template <class T> friend void u_function_template_declared_before(T);
    template <class T> friend void u_function_template_declared_after(T);
    template <class T> friend void u_function_template_declared_in_cpp(T);
    template <class T> friend void u_function_template_defined_here(T) { }
    template <class T> friend void u_function_template_defined_before(T);
    template <class T> friend void u_function_template_defined_after(T);
    template <class T> friend void u_function_template_defined_in_cpp(T);

    template <class T> class u_class_template_defined_in_class_before { };

    template <class T> friend class u_class_template_undeclared;
    template <class T> friend class u_class_template_declared_before;
    template <class T> friend class u_class_template_declared_after;
    template <class T> friend class u_class_template_declared_in_cpp;
    template <class T> friend class u_class_template_defined_in_class_before;
    template <class T> friend class u_class_template_defined_in_class_after;
    template <class T> friend class u_class_template_defined_before;
    template <class T> friend class u_class_template_defined_after;
    template <class T> friend class u_class_template_defined_in_cpp;

    template <class T> class u_class_template_defined_in_class_after { };
};

void u_function_declared_after();
void u_function_defined_after() { }
class u_class_declared_after;
class u_class_defined_after { };
template <class T> void u_function_template_declared_after(T);
template <class T> void u_function_template_defined_after(T) { }
template <class T> class u_class_template_declared_after;
template <class T> class u_class_template_defined_after { };

void i_function_declared_before();
void i_function_defined_before() { }
class i_class_declared_before;
class i_class_defined_before { };
template <class T> void i_function_template_declared_before(T);
template <class T> void i_function_template_defined_before(T) { }
template <class T> class i_class_template_declared_before;
template <class T> class i_class_template_defined_before { };

template <class C>
class i
{
    friend void i_function_undeclared();
    friend void i_function_declared_before();
    friend void i_function_declared_after();
    friend void i_function_declared_in_cpp();
    friend void i_function_defined_here(C*) { }
    friend void i_function_defined_before();
    friend void i_function_defined_after();
    friend void i_function_defined_in_cpp();

    class i_class_defined_in_class_before { };

    friend class i_class_undeclared;
    friend class i_class_declared_before;
    friend class i_class_declared_after;
    friend class i_class_declared_in_cpp;
    friend class i_class_defined_in_class_before;
    friend class i_class_defined_in_class_after;
    friend class i_class_defined_before;
    friend class i_class_defined_after;
    friend class i_class_defined_in_cpp;

    class i_class_defined_in_class_after { };

    template <class T> friend void i_function_template_undeclared(T);
    template <class T> friend void i_function_template_declared_before(T);
    template <class T> friend void i_function_template_declared_after(T);
    template <class T> friend void i_function_template_declared_in_cpp(T);
    template <class T> friend void i_function_template_defined_here(T) { }
    template <class T> friend void i_function_template_defined_before(T);
    template <class T> friend void i_function_template_defined_after(T);
    template <class T> friend void i_function_template_defined_in_cpp(T);

    template <class T> class i_class_template_defined_in_class_before { };

    template <class T> friend class i_class_template_undeclared;
    template <class T> friend class i_class_template_declared_before;
    template <class T> friend class i_class_template_declared_after;
    template <class T> friend class i_class_template_declared_in_cpp;
    template <class T> friend class i_class_template_defined_in_class_before;
    template <class T> friend class i_class_template_defined_in_class_after;
    template <class T> friend class i_class_template_defined_before;
    template <class T> friend class i_class_template_defined_after;
    template <class T> friend class i_class_template_defined_in_cpp;

    template <class T> class i_class_template_defined_in_class_after { };
};

void i_function_declared_after();
void i_function_defined_after() { }
class i_class_declared_after;
class i_class_defined_after { };
template <class T> void i_function_template_declared_after(T);
template <class T> void i_function_template_defined_after(T) { }
template <class T> class i_class_template_declared_after;
template <class T> class i_class_template_defined_after { };

// ----------------------------------------------------------------------------
// Copyright (C) 2014 Bloomberg Finance L.P.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
// ----------------------------- END-OF-FILE ----------------------------------
