namespace BloombergLP {

namespace txt {

class FuncSec {
    // Class doc

    static int wildClassMethod();
        // Problem -- not in section

    FuncSec(double d);
        // Problem -- not in section

    void wildManip();
        // Problem -- not in section

    int wildAcc() const;
        // Problem -- not in section

    // CLASS METHODS
    static int woof();
        // this should be OK

    int woofBad();
        // not static -- error

    int woofBadConst() const;
        // not static -- error

    FuncSec();
        // Problem -- c'tor in 'CLASS METHODS' section

    // CREATORS
    FuncSec();
        // should be OK

    FuncSec(int i);                                                 // IMPLICIT
        // should be OK

    FuncSec(int j);
        // Problem -- not marked 'implicit' or 'explicit'

    FuncSec(int k);                                                // IMPLICIT
        // Problem -- 'IMPLICIT' aligned wrong

    FuncSec(int j, char c = 0);                                     // IMPLICIT
        // Should be OK

    FuncSec(int j, char c = 0);
        // Problem -- not marked 'implicit' or 'explicit'

    FuncSec(int j, int k = 3, char c = 0);                          // IMPLICIT
        // Should be OK

    FuncSec(int j, int k = 3, char c = 0);
        // Problem -- not marked 'implicit' or 'explicit'

    ~FuncSec();
        // Should be OK

    void woofManip();
        // Problem -- manipulator in 'CREATORS' section

    static
    void woofStatic();
        // Problem -- static in 'CREATORS' section

    void woofAcc() const;
        // Problem -- accessor in 'CREATORS' section

    // MANIPULATORS
    FuncSec();
        // Problem -- c'tor in 'MANIPULATORS' section

    void woofManip();
        // Should be OK

    static
    void woofStatic();
        // Problem -- static manip

    void woofConst() const;
        // Problem -- const manip

    // ACCESSORS
    FuncSec();
        // Problem -- c'tor in 'ACCESSORS' section

    void woofAcc() const;
        // Should be OK

    void woofManip();
        // Problem -- non-const ACCESSOR

    static
    void woofStatic();
        // Problem -- static ACCESSOR
};

}  // close package namespace

}  // close enterprise namespace
