
static
SYSUTIL_IDENT_RCSID(woof);

BDES_IDENT_RCSID(bdesu_stacktraceresolverimpl_xcoff_cpp,"$Id$ $CSID$")

static
BDES_IDENT_RCSID(bdesu_stacktraceresolverimpl_xcoff_cpp,"$Id$ $CSID$")

static int i1;

static void woof1(int i)
    // woof
{
    ++i;
}

namespace BloombergLP {

static int i1;

static void woof2(int i)
    // woof
{
    ++i;
}

int notDocumented1();    // OK -- outside class

namespace {    // should be caught
    int woof;    // not curently caught

    int woofInUnnamed();
        // not caught
}  // close unnamed namespace

class txt_TestWoofer {
    static int s_i;

    int d_i;

    // CLASS METHODS
    static woofStatic();
        // static method

    // CREATORS
    txt_TestWoofer();
        // default

    txt_TestWoofer(const txt_TestWoofer& original);
        // copy

    ~txt_TestWoofer();
        // d'tor

    // MANIPULATORS
    void notDocumented2();
};

// FREE OPERATORS
bsl::ostream& operator<<(bsl::ostream&                    stream,
                         baetzo_LocalTimeValidity::Status value);
    // Write the string representation of the specified enumeration 'value' to
    // the specified output 'stream', and return a reference to the modifiable
    // 'stream'.  (See 'toAscii' for what constitutes the string representation
    // of a 'baetzo_LocalTimeValidity::Status' value.)

bool operator==(int lhs, int rhs);

A& operator++(A& a);

// ===========================================================================
//                      INLINE FUNCTION DEFINITIONS
// ===========================================================================

                     // -------------------------------
                     // struct baetzo_LocalTimeValidity
                     // -------------------------------

// FREE OPERATORS
inline
bsl::ostream& operator<<(bsl::ostream&                    stream,
                         baetzo_LocalTimeValidity::Status value)
{
    return baetzo_LocalTimeValidity::print(stream, value);
}

}  // close namespace BloombergLP

namespace {
}

class txt_TestArf {
    int d_i;
    int d_j;

    int i() { return d_i; }
        // not allowed

    int j() {
        // not allowed

        return d_j;
    }

    int iTimesJ()
        // doc
    {
        return d_i * d_j;
    }
};

void woof() {
    // not allowed
}

int arf() { return 3; }
    // not allowed

struct txt_TestMeow {
    Boom::Town oil1()
                     = 0;
        // doc

    Boom::Town oil2()
                     const
                     = 0;
        // doc

    Boom::Town oil3()
                     = 0;

    Boom::Town oil4()
                     const
                     = 0;
};

int arf10()
{
    for (int i = 0; i < 10; ++i) {
       	for (int j = 0; i < 10; ++j) {
 	    int k = i * j;
  	    k *= k;
   	    k += k;
    	    k -= k;
     	    k ^= k + 1;
      	    k = ~k;
       	    --k;
	}
    }
}

class txt_TestMeow {
    // class doc

  public:
    int arf11(int& visitor);
        // arf11 doc

    int arf12(int& manipulator);
        // arf12 doc

    int arf13(int& accessor);
        // arf13 doc

    int arf14(ACCESSOR& a);
        // arf14 doc

    int arf15(int& a);
        // arf15 doc
};

namespace abc { class Def; }

int arf16(int&& a);

class Test {
    // This class name should be legal
};

class TestWoofer {
    // This class name should be legal
};

void operator<<(bsl::ostream& x, const Woofer& y);

void operator<<(bsl::ostream& x, Woofer& y);

void operator>>(bsl::ostream& x, Woofer& y);

class Woofer {
    // This class name should be illegal

    // CREATORS
    Woofer();
        // C'tor
    //! Woofer(const Woofer&) = default;
    ~Woofer();
        // D'tor
    Woofer(int i,
           int j = 5);
        // C'tor

    // MANIPULATORS
    Woofer& operator=(const Woofer& rhs);
        // Assign

    Woofer& operator=(const Woofer& other);
        // Assign

    // ACCESSORS
    bsl::ostream& print(bsl::ostream& stream,
                        int           level = 0,
                        int           spacesPerLevel = 4) const;
        // Doc.
};
