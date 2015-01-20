template <typename T> void g(T);

void f(long &long_val)
{
    g((long *)&long_val);
    g((float *)&long_val);
    g((char *)&long_val);
    g((long &)long_val);
    g((float &)long_val);
    g((char &)long_val);
    g((const long &)long_val);
    g((const float &)long_val);
    g((const char &)long_val);
    g((const long *)&long_val);
    g((const float *)&long_val);
    g((const char *)&long_val);
    g((long *)long_val);
    g((float *)long_val);
    g((char *)long_val);
}

void f(long *long_ptr)
{
    g((long *)&long_ptr);
    g((float *)&long_ptr);
    g((char *)&long_ptr);
    g((long &)long_ptr);
    g((float &)long_ptr);
    g((char &)long_ptr);
    g((const long &)long_ptr);
    g((const float &)long_ptr);
    g((const char &)long_ptr);
    g((const long *)&long_ptr);
    g((const float *)&long_ptr);
    g((const char *)&long_ptr);
    g((long *)long_ptr);
    g((float *)long_ptr);
    g((char *)long_ptr);
}

void f(long **long_long_ptr)
{
    g((long *)&long_long_ptr);
    g((float *)&long_long_ptr);
    g((char *)&long_long_ptr);
    g((long &)long_long_ptr);
    g((float &)long_long_ptr);
    g((char &)long_long_ptr);
    g((const long &)long_long_ptr);
    g((const float &)long_long_ptr);
    g((const char &)long_long_ptr);
    g((const long *)&long_long_ptr);
    g((const float *)&long_long_ptr);
    g((const char *)&long_long_ptr);
    g((long *)long_long_ptr);
    g((float *)long_long_ptr);
    g((char *)long_long_ptr);
}

