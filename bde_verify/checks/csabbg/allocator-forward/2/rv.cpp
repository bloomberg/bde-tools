namespace BloombergLP { namespace bslma { class Allocator; } }

struct A { explicit A(BloombergLP::bslma::Allocator * = 0); };
struct B { };

void f(A *);
void f(B *);
void f(void *);
void f(char *);
void f(int *);
void f(char *, int);
void f(int *, int);
void f(char *, unsigned);
void f(int *, unsigned);

void g(int *);
int g();

struct C {
    explicit C(A *);
    explicit C(B *);
    explicit C(void *);
    explicit C(char *);
    explicit C(int *);
    explicit C(char *, int);
    explicit C(int *, int);
    explicit C(char *, unsigned);
    explicit C(int *, unsigned);

    void f(A *);
    void f(B *);
    void f(void *);
    void f(char *);
    void f(int *);
    void f(char *, int);
    void f(int *, int);
    void f(char *, unsigned);
    void f(int *, unsigned);

    void g(int *);
    int g();
};
