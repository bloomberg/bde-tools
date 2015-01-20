#include <friends.h>

void c_function_declared_in_cpp();
void c_function_defined_in_cpp() { }

class c_class_declared_in_cpp;
class c_class_definedd_in_cpp { };

template <class T> void c_function_template_declared_in_cpp(T);
template <class T> void c_function_template_defined_in_cpp(T) { }

template <class T> class c_class_template_declared_in_cpp;
template <class T> class c_class_template_defined_in_cpp { };

void u_function_declared_in_cpp();
void u_function_defined_in_cpp() { }

class u_class_declared_in_cpp;
class u_class_definedd_in_cpp { };

template <class T> void u_function_template_declared_in_cpp(T);
template <class T> void u_function_template_defined_in_cpp(T) { }

template <class T> class u_class_template_declared_in_cpp;
template <class T> class u_class_template_defined_in_cpp { };

void i_function_declared_in_cpp();
void i_function_defined_in_cpp() { }

class i_class_declared_in_cpp;
class i_class_definedd_in_cpp { };

template <class T> void i_function_template_declared_in_cpp(T);
template <class T> void i_function_template_defined_in_cpp(T) { }

template <class T> class i_class_template_declared_in_cpp;
template <class T> class i_class_template_defined_in_cpp { };

template class i<void>;
template class i<int>;

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
