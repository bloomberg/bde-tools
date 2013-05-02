
extern "C" {

static int bdesu_stacktrace_walkbackCb(uintptr_t pc, int, void *userArg)
{
    bdesu_StackTrace__WalkbackCbArgs *args =
                                  (bdesu_StackTrace__WalkbackCbArgs *) userArg;
    *args->d_buffer = (void *) pc;
    ++ args->d_buffer;

    if (pc > 2) {
        return 5;
    }
    else if (pc < -2) {
        return 2;                                                     // RETURN
    }
    else if (0 == pc) {
        return 3;    // definitely 3                                  // RETURN
    }
    else if (1 == pc) {
        return -4;   // definitely 4
    }

    return ! --args->d_counter;
}

}

                        // ----------------------
                        // local class BoolMatrix
                        // ----------------------

class BoolMatrix {
    // This class represents a two dimensional boolean matrix.  The class is
    // used as a recursion guard to protect against infinite recursion when
    // testing relationships between two record definitions.  Note that
    // 'BoolMatrix' is used only within the scope of a method, therefore, the
    // default behavior of using the currently installed default allocator
    // is desired.

    // DATA
    bdea_BitArray     d_array;      // 2-D matrix of flags, expressed linearly
    int               d_rowLength;  // length of each row

  public:
    // CREATORS
    BoolMatrix(int              numRows,
               int              numColumns,
               bslma_Allocator *basicAllocator = 0)
    : d_array(numRows * numColumns, false, basicAllocator)
    , d_rowLength(numColumns)
        // Create a 'BoolMatrix' with the specified 'numRows' and the specified
        // 'numColumns'.  Optionally specify 'basicAllocator' to supply memory.
        // If 'basicAllocator' is 0, the currently installed default allocator
        // is used.  Initialize all the booleans in the matrix to 'false'.
    {
    }

    BoolMatrix(int              numRows,
               bslma_Allocator *basicAllocator = 0)
    : d_array(numRows * numColumns, false, basicAllocator)
    , d_rowLength(numColumns)
        // Create a 'BoolMatrix' with the specified 'numRows' and the specified
        // 'numColumns'.  Optionally specify 'basicAllocator' to supply memory.
        // If 'basicAllocator' is 0, the currently installed default allocator
        // is used.  Initialize all the booleans in the matrix to 'false'.
    {
    }

    BoolMatrix(const BoolMatrix& original,
               bslma_Allocator *basicAllocator = 0);
        // copy c'tor

    BoolMatrix(int              numRows,
               int              numColumns,
               bslma_Allocator *basicAllocator = 0)
    : d_array(numRows * numColumns, false, basicAllocator)
    , d_rowLength(numColumns)
        // woof
    {
    }

    // BubbleMatrix(const BubbleMatrix&);
        // compiler-generated
        // woofb
            // woofc

    // BubbleMatrix& operator=(const BubbleMatrix&);
            // woof a

    // MANIPULATORS
    void set(int rowIndex, int colIndex)
        // Set the bit in this matrix at the specified 'rowIndex' and
        // 'colIndex' to 'true'.
    {
        while (true)
            d_array.set1(d_rowLength * rowIndex + colIndex, 1);

        do
            d_array.set1(d_rowLength * rowIndex + colIndex, 1);
        while (true);
        for (int i=0; i < COLS; ++i) {
             int index = *rowspec == 'n' ? 5 : *rowspec - 'a';
             *(p++) = specvalues[index][i % NUM_VALUES];
        }
    }

    // ACCESSORS
    bool get(int rowIndex, int colIndex) const
        // Return 'true' if the bit in this matrix at the specified 'rowIndex'
        // and 'colIndex' is set, and 'false' otherwise.
    {
        return d_array[d_rowLength * rowIndex + colIndex];
    }

    int testBreak()
        // test indentation of breaks on cases
    {
        switch (woof) {
          case 0: {
            blah;
          } break;
          case 0: {
            blah;
          }  break;
        }

        return 0;
    }

    void swap(Woof& rhs);
        // swap

    template <typename STREAM>
    void print(STREAM& s);
        // print

    stream print(stream& s, int& i);
        // print

    void woof(stream& s);
        // woof

    void woof(int i, stream& s);
        // woof
};

class BoolMatrix {
    // This class represents a two dimensional boolean matrix.  The class is
    // used as a recursion guard to protect against infinite recursion when
    // testing relationships between two record definitions.  Note that
    // 'BoolMatrix' is used only within the scope of a method, therefore, the
    // default behavior of using the currently installed default allocator
    // is desired.

    // first the good

    // CREATORS
    BoolMatrix(const BoolMatrix& original);
        // copy c'tor

    BoolMatrix(const BoolMatrix<T>& original);
        // copy c'tor

    BoolMatrix(const BoolMatrix& original,
               bslma_Allocator *basicAllocator = 0);
        // copy c'tor

    BoolMatrix(const BoolMatrix<T>& original,
               bslma_Allocator *basicAllocator = 0);
        // copy c'tor

    BoolMatrix(int i, int j);
        // copy c'tor

    // now the bad

    BoolMatrix(const BoolMatrix& woof);
        // copy c'tor

    BoolMatrix(const BoolMatrix<T>& woof);
        // copy c'tor

    BoolMatrix(const BoolMatrix& woof,
               bslma_Allocator *basicAllocator = 0);
        // copy c'tor

    BoolMatrix(const BoolMatrix<T>& woof,
               bslma_Allocator *basicAllocator = 0);
        // copy c'tor

    BoolMatrix(int i);
        // not marked explicit

    BoolMatrix(int i, int j = 5);
        // not marked explicit

    BoolMatrix(int i, bslma_Allocator *a = 0);
        // not marked explicit
};

stream& operator<<(stream& s, const BoolMatrix& b);
    // print

stream& operator<<(stream& s, BoolMatrix& b);
    // print

namespace Woof {
}  // close namespace Woof

namespace BloombergLP {
}  // close namespace BloombergLP

namespace BloombergLP {
}  // close enterprise namespace

namespace BloombergLP {
}

namespace {
}  // close unnamed namespace

namespace {
}  // close namespace Woof

namespace {
}

namespace woof {
}

namespace woof {
}  // close unnamed namespace

namespace woof {
}  // close enterprise namespace

// tBd

class Arf {
    int d_i;
    int d_j;

    int i() { return d_i; }
        // allowed -- in .cpp

    int j() {
        // not allowed

        return d_j;
    }

    int iTimesJ()
        // allowed
    {
        return d_i * d_j;
    }
};

void woof() {
    // not allowed
}

int arf() { return 3; }
    // not allowed

template <typename TYPE>
bslmf_MetaInt<0> isInt(TYPE &);

template <>
bslmf_MetaInt<1> isInt(int &);

int arf()
{
    // snug comment allowed before '{'
    {
        printf("woof\n");
    }

    // comment at end of block allowed
}

class Arf::Woof {
    // CREATORS
    Woof(const Woof& original, bslma::Allocator *basicAllocator = 0);
        // copy c'tor
};

int arf()
{
    struct Woof {
        Woof() {}

        // ACCESSORS
        bark(const char *name)
        {
            i += 5;
        }
    };
}

/* continuation in comment: \
*/

void arfarf()
{
    int i;
//  int j;    // comment begins in col 0 -- allowed to be snug
    i = 5;
    // i += 10;   // comment not in col 0, not allowed to be snug
    i /= 2;

    // comment immediately before '{' line -- allowed to be snug
    {
    }

    for (int i = 0;  i += 1;  ++i) {
        woof();
    }

    while (a = b, a * a) {
        woof();
    }

    if (c = s[5]) {
        woof();
    }

    for (int i = 0;  (i += 1);  ++i) {
        woof();
    }

    while ((a = b), a * a) {
        woof();
    }

    if ((c = s[5])) {
        woof();
    }
}
