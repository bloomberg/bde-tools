struct NoDtor { };
struct Dtor { ~Dtor(); };
struct ContainsNoDtor { NoDtor x; };
struct ContainsDtor { Dtor x; };
struct InheritsNoDtor : NoDtor { };
struct InheritsDtor : Dtor { };

int main()
{
    NoDtor();
    Dtor();
    ContainsNoDtor();
    ContainsDtor();
    InheritsNoDtor();
    InheritsDtor();
}
