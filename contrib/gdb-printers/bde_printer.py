"""
   GDB pretty printer support for BDE components

   This module provides a set of pretty printers to load into gdb for debugging
   code using BDE (http://github.com/bloomberg/bde) components.

   This is a work in progress, more printers will be added as needed.

   Authors: David Rodriguez Ibeas <dribeas@bloomberg.net>
            Evgeny Yakimov        <eyakimov@bloomberg.net>
            Hyman Rosen           <hrosen4@bloomberg.net>

   List of provided pretty printers
   --------------------------------

    Printer           Implementation type
    ---------------   -----------------------------------------------------
    BDE
      ManagedPtr      BslmaManagedPtr
      atomic          BslAtomic
      map             BslMap
      pair            BslPair
      set             BslSet
      shared_ptr      BslSharedPtr
      string          BslString
      unordered_map   BslUnorderedMap
      unordered_set   BslUnorderedSet
      vector          BslVector
      weak_ptr        BslSharedPtr

    [implementation details]
      ContainerBase   ContainerBaseBslma
      StringImp       BslStringImp
      VectorImp       BslVectorImp

   Configuration options
   ---------------------
    These settings configure some of the behavior of the pretty printer to
    improve access to different elements in the underlying data.

        (gdb) set print bslma-allocator on

    Setting           Meaning
    ---------------   -----------------------------------------------------
    bslma-allocator   Controls whether the bslma::Allocator* is printed

    bsl-eclipse       Controls output format, set to 'on' inside Eclipse
                      and leave as 'off' for plain gdb.

   Usage
   -----
    To use the pretty printers load the script into gdb, either manually
    through:

        (gdb) python execfile('/path/to/this/script.py')

    or automatically at start up.  See the gdb documentation on how to setup
    automatic loading of pretty printers.

    You can list, enable or disable pretty printers by using the gdb commands:

        (gdb) info    pretty-printer
        (gdb) disable pretty-printer global BDE;vector
        (gdb) enable  pretty-printer global BDE

    Additionally, you can ignore the pretty printer for a single 'print'
    command by running it in "raw" mode:

        (gdb) print /r container

   General design considerations
   -----------------------------

    Pretty printers should focus on the useful information for the developer
    that is debugging the application.  What is useful for one developer might
    be too verbose for another and not enough for a third one.  Unless
    otherwise noted the provided pretty printers will reformat the available
    information but avoid hiding data from the developer.  The implication is
    that the output might be slightly verbose (the 'bslma::Allocator' pointer
    in containers is printed always, the size and capacity for 'bsl::string' is
    printed...).  Other existing pretty printers (for example for the standard
    library provided with gcc) will omit details and focus on the data.

    The format used for output has been considered for a high information
    density given that it will print more things than needed by most users.
    The description of the format for each one of the pretty printers is
    documented below and does not reflect the layout of the C++ types that are
    being printed.
"""
import re
import gdb
import gdb.printing

###############################################################################
# Private Types and Helpers
###############################################################################

boolType = None

##  Helpers controlling the printout based on printer options
def _createAllocatorList(cbase):
    """Create a list with the allocator information if 'print bslma-allocator'
       is set or empty otherwise.
    """
    printAllocator = gdb.parameter('print bslma-allocator')
    return [] if not printAllocator else [('alloc',cbase)]

def _sizeAndAllocator(size, allocator):
    printAllocator = gdb.parameter('print bslma-allocator')
    return ('size:%d' % size if not printAllocator else
            'size:%d,alloc:%s' % (size,allocator))

def keyValueIterator(arg):
    eclipseMode = gdb.parameter('print bsl-eclipse')
    if eclipseMode:
        return RawKeyValueIterator(arg)
    else:
        return KeyValueIterator(arg)

def valueIterator(arg):
    eclipseMode = gdb.parameter('print bsl-eclipse')
    if eclipseMode:
        return RawValueIterator(arg)
    else:
        return ValueIterator(arg)

## Debug catch all pretty printer
class CatchAll:
    """Not a pretty printer

    This type complies with the pretty printer interface, but will open an
    interactive python shell with the information available to the printer for
    debugging and testing purposes.
    """
    def __init__(self,val):
        """Store the gdb value in this object and open an interactive shell"""
        self.val = val
        import code; code.interact(local=locals())

    def to_string(self):
        import code; code.interact(local=locals())
        return "<------>"

class ContainerBaseBslma:
    """Printer for the ContainerBase<bsl::allocator<T>> specializations.

    The BDE library is mostly compatible with the C++03 standard containers,
    but differs in the use of allocators.  In particular, the default allocator
    used in containers is a wrapper, 'bsl::allocator<>' around a polymorphic
    allocator, 'bslma::Allocator'.  To handle standard-compliant allocators and
    polymorphic allocators, the real allocator is handled in a base template
    'BloombergLP::bslalg::ContainerBase'.  Since polymorphic allocators are the
    default, the pretty printer only handles this case.

    The pretty printer for the 'ContainerBase' type will print the address of
    the 'bslma::Allocator' ('mechanism') in use by the container.  GDB is kind
    enough to print out the name of the instance if it refers to a variable
    with static lifetime so the format may look like either of the following:

        mechanism = <BloombergLP::g_newDeleteAllocatorSingleton>

        mechanism = 0x87639180

    Note: This is not intended for direct use.
    Note: This pretty printer ignores the hint to print the allocator.
    """

    def __init__(self,val):
        self.val            = val
        self.bslmaAllocator = self.val['d_allocator']['d_mechanism']

    def to_string(self):
        return self.bslmaAllocator

class BslStringImp:
    """Pretty printer for 'bsl::String_Imp<char>'

    The implementation of 'bsl::string' ('bsl::basic_string<>' template) uses a
    base template 'bsl::String_Imp<>' to handle the actual contents.  This
    implementation uses a small string optimization with an internal buffer
    that depends on the architecture.  The pretty printer for this type will
    print a compact representation of the available information, encoding in
    the capitalization of the message whether the current object is using the
    small buffer ('size') or the dynamically allocated large buffer ('Size').

        data = [size:5,capacity:19] "short"
        data = [Size:24,capacity:34] "This is a long string!!!"

    The size of the internal buffer is detected at runtime.

    Note that the pretty printer only handles narrow character strings,
    'bsl::string', and not wide character strings 'bsl::wstring' or any other
    specilization of the 'bsl::basic_string<>' template.

    The current implementation in BDE will set the length value to
    'bsl::string::npos' on destruction.  The pretty printer detects this as a
    special value and reports that the string has been destroyed.  If the
    capacity of the string indicates that it was using the small string
    optimization it then attempts to print the contents of the buffer, if the
    small string optimization is not in place, the pretty printer will attempt
    to print the contents of 'd_start_p' (pointer to the string that *has
    already been deallocated*).  Note that this is a *best effort* with no
    guarantees, the object has been destroyed, the value may have already been
    reused.

    Note: This is not intended for direct use.

    Note: The implementation is not able to print strings with a length
          greater or equal to 2^31.
    """
    def __init__(self,val):
        """Precalculate the data needed to later print the string"""
        self.val      = val
        length = val['d_length']
        if str(length) == '4294967295':
            self.destroyed = True
            self.length    = int(-1)
        else:
            self.destroyed = False
            self.length   = int(val['d_length'])
        self.capacity = int(val['d_capacity'])
        short = val['d_short']
        self.isShort  = (self.capacity < short.type.sizeof)
        self.buffer   = (short['d_data']['d_buffer'] if self.isShort else
                         val['d_start_p'])

    def to_string(self):
        """Format the string"""
        str = None
        if not self.destroyed:
            str = '[%s:%d,capacity:%d] "%s"' % (
                                        'size' if self.isShort else 'Size',
                                        self.length,
                                        self.capacity,
                                        self.buffer.string(length=self.length))
        else:
            if self.isShort:
                str = '[DESTROYED, small buffer value]: %s' % self.buffer
            else:
                str = '[DESTROYED] %s' % self.buffer
        return str

class BslVectorImp:
    """Printer for 'bsl::Vector_ImpBase<T>' specializations.

    This pretty printer handles printing instances of the
    'bsl::Vector_ImpBase<>' template used to hold the contents of
    'bsl::vector<>'.  The printer will dump the size and capacity of the
    object followed by the sequence of values in the sequence.

        [size:10,capacity:16] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}

    Note: This is not intended for direct use
    """
    def __init__(self, val):
        self.val = val
        self.begin    = val['d_dataBegin']
        self.end      = val['d_dataEnd']
        self.size     = int(self.end - self.begin)
        self.capacity = int(val['d_capacity'])

    def to_string(self):
        return '[size:%d,capacity:%d]' % (self.size, self.capacity)

    def display_hint(self):
        return 'map'

    def children(self):
        class VectorContentsIterator:
            """Iterator over the contents of the vector"""
            def __init__(s, begin, end):
                self.begin   = begin
                self.end     = end
                self.current = begin

            def __iter__(s):
                return s

            def next(s):
                if self.current == self.end:
                    raise StopIteration

                name  = int(self.current - self.begin)
                value = self.current.dereference()

                self.current += 1

                return (name, value)

        return keyValueIterator(VectorContentsIterator(self.begin, self.end))

class BslRbTreeIterator:
    """Helper class to produce iterations over a RB-tree

    This is **not** a pretty printer, but a helper class to aid in the
    implementation of pretty printers for sorted associative containers using
    RB-Trees as underlying data structure.
    """
    def __init__(self, type, sentinel):
        self.sentinel = sentinel
        self.current  = sentinel['d_right_p']
        self.nodeType  = gdb.lookup_type('BloombergLP::bslstl::TreeNode<%s>'
                                                % type)

    def __iter__(self):
        return self

    def next(self):
        if (self.current == self.sentinel.address):
            raise StopIteration
        treeNode = self.current.dereference().cast(self.nodeType)
        self.current = self.nextNode(self.current)
        return treeNode['d_value']

    def followPointer(self, pointer, name):
        """Follow the pointer specified by 'name' in the specified 'object'.

        This function implements the equivalent in C++ of:
            return pointer->name & ~1
        """
        next = pointer.dereference()[name]
        if long(next) & 1:
            next = gdb.Value(long(next)&~1).reinterpret_cast(next.type)
        return next

    def nextNode(self, pointer):
        if (pointer['d_right_p'] != 0):
            pointer = self.followPointer(pointer,'d_right_p')
            l = self.followPointer(pointer,'d_left_p')
            while not l == 0:
                pointer = l
                l = self.followPointer(pointer,'d_left_p')
        else:
            p = self.followPointer(pointer, 'd_parentWithColor_p')
            while p != self.sentinel.address and self.followPointer(
                                                    p, 'd_right_p') == pointer:
                pointer = p
                p = self.followPointer(p, 'd_parentWithColor_p')
            pointer = p
        return pointer

class HashTableIterator:
    """Helper class to produce iterations over a hash table"""
    def __init__(self, type, sentinel):
        self.nodeType = gdb.lookup_type(
            'BloombergLP::bslalg::BidirectionalNode<%s>' % type)
        self.current = sentinel.cast(self.nodeType.pointer())

    def __iter__(self):
        return self

    def next(self):
        if self.current == 0:
            raise StopIteration
        value = self.current.dereference()['d_value']
        self.current = self.current['d_next_p'].cast(self.nodeType.pointer())
        return value

class PairTupleIterator:
    """Helper class to convert bsl::pair to a tuple as an iterator"""

    def __init__(self,iter):
        self.iter = iter;

    def __iter__(self):
        return self

    def next(self):
        nextPair = self.iter.next()
        return (nextPair['first'],nextPair['second'])

class KeyValueIterator:
    """This iterator converts an iterator of pairs into 2 alternating tuples.
    """
    def __init__(self,iter):
        self.value  = None
        self.iter = iter;

    def __iter__(self):
        return self

    def next(self):
        if not self.value:
            next = self.iter.next()
            result     = ('key',   next[0])
            self.value = ('value', next[1])
            return result
        else:
            result     = self.value
            self.value = None
            return result

class ValueIterator:
    """This iterator returns a ('value',value) tuple from an iterator."""
    def __init__(self,iter):
        self.iter = iter;

    def __iter__(self):
        return self

    def next(self):
        value = self.iter.next()
        return ('value',value)

class RawKeyValueIterator:
    """This iterator returns a (str(key),value) tuple from an iterator."""
    def __init__(self,iter):
        self.iter = iter;

    def __iter__(self):
        return self

    def next(self):
        next = self.iter.next();
        return (str(next[0]),next[1])

class RawValueIterator:
    """This iterator returns a (str(value),value) tuple from an iterator."""
    def __init__(self,iter):
        self.iter = iter;

    def __iter__(self):
        return self

    def next(self):
        value = self.iter.next()
        return (str(value),value)


###############################################################################
# Public Type Printers
###############################################################################
class IPv4Address:
    """Pretty printer for 'bteso_IPv4Address'

    Prints the address in dotted decimal notation with the port separated by a
    colon.

         192.10.1.5:8194
    """
    def __init__(self,val):
        self.val  = val
        self.port = val['d_portNumber']
        ip = int(val['d_address'])
        self.a    =  ip        & 0xFF
        self.b    = (ip >>  8) & 0xFF
        self.c    = (ip >> 16) & 0xFF
        self.d    = (ip >> 24) & 0xFF

    def to_string(self):
        return "%d.%d.%d.%d:%d" % (self.a, self.b, self.c, self.d, self.port)

class Nullable:
    """Pretty printer for 'bdeut_NullableValue<T>'

    This pretty printer handles both the allocator aware and not allocator
    aware types internally.

    The output of the pretty printer is split into a 'null' output and
    optionally a 'value' if not null.
    """
    def __init__(self,val):
        self.val   = val
        self.type  = val.type.template_argument(0)
        self.members = []
        if val['d_imp'].type.has_key('d_allocator_p'):
            alloc = val['d_imp']['d_allocator_p']
            self.members.append(('alloc',alloc))

        self.members.append(('null', val['d_imp']['d_isNull']))
        if not val['d_imp']['d_isNull']:
            buf   = val['d_imp']['d_buffer']['d_buffer']
            self.members.append(('value',
                                 buf.cast(self.type.pointer()).dereference()))

    def to_string(self):
        return str(self.val.type)

    def children(self):
        return iter(self.members)

class Time:
    """Pretty printer for 'bdet_Time'

    This pretty printer shows the value of the time object in 'hh:mm:ss.xxx'
    format.
    """
    def __init__(self, val):
        self.val = val

    def to_string(self):
        tmp = int(self.val['d_milliseconds'])
        ms  = tmp % 1000
        tmp = tmp / 1000
        sec = tmp % 60
        tmp = tmp / 60
        min = tmp % 60
        hh = tmp / 60

        return "%02d:%02d:%02d.%03d" % (hh, min, sec, ms)

class Date:
    """Pretty printer for 'bdet_Date'

    This pretty printer shows the value of the date in 'YYYYY-MM-DD' format.

    Note: The implementation of the pretty printer is incomplete and is only
    precise for "recent" dates.
    """
    SEPTEMBER = 9
    YEAR_1752 = 1752
    YEAR_1601 = 1601
    JAN_01_1753 = 639908
    JAN_01_1601 = 584401
    YEAR_1752_FIRST_MISSING_DAY = 3
    YEAR_1752_NUM_MISSING_DAYS  = 11
    DAYS_IN_NON_LEAP_YEAR       = 365
    DAYS_IN_LEAP_YEAR           = DAYS_IN_NON_LEAP_YEAR + 1
    DAYS_IN_4_YEARS             = 3 * DAYS_IN_NON_LEAP_YEAR + DAYS_IN_LEAP_YEAR
    DAYS_IN_100_YEARS           = 25 * DAYS_IN_4_YEARS - 1
    DAYS_IN_400_YEARS           = 4 * DAYS_IN_100_YEARS + 1

    y1752DaysThroughMonth = [
        0, 31,  60,  91, 121, 152, 182, 213, 244, 263, 294, 324, 355 ]
    normDaysThroughMonth  = [
        0, 31,  59,  90, 120, 151, 181, 212, 243, 273, 304, 334, 365 ]
    leapDaysThroughMonth  = [
        0, 31,  60,  91, 121, 152, 182, 213, 244, 274, 305, 335, 366 ]

    def __init__(self, val):
        self.val = val

    def serialToYearDate(self, serialDay):
        """Extract the year and day of the year from the value in 'serialDay'.
        """
        if serialDay > Date.JAN_01_1753:
            y = Date.YEAR_1601                 # base year
            n = serialDay - Date.JAN_01_1601   # num actual days since 1601/1/1

            m = n + Date.YEAR_1752_NUM_MISSING_DAYS - 1
                # Compensate for the 11 missing days in September of 1752, and
                # the additional leap day in 1700.

            z400 = m / Date.DAYS_IN_400_YEARS     # num 400-year blocks
            y += z400 * 400
            m -= z400 * Date.DAYS_IN_400_YEARS    # num days since y/1/1 (400)

            z100 = m / Date.DAYS_IN_100_YEARS     # num 100-year blocks
            y += z100 * 100
            m -= z100 * Date.DAYS_IN_100_YEARS    # num days since y/1/1 (100)

            z4 = m / Date.DAYS_IN_4_YEARS         # num 4-year blocks
            y += z4 * 4
            m -= z4 * Date.DAYS_IN_4_YEARS        # num days since y/1/1 (4)

            z = m / Date.DAYS_IN_NON_LEAP_YEAR    # num whole years
            y += z
            m -= z * Date.DAYS_IN_NON_LEAP_YEAR   # num days since y/1/1 (1)

            if (0 == m and (4 == z or 4 == z100)):# last day in a leap yeear or
                                                  # a leap year every 400 years
                year      = y - 1
                dayOfYear = Date.DAYS_IN_LEAP_YEAR
            else:
                year      = y
                dayOfYear = m + 1
            return (year, dayOfYear)
        else:
            # Date pre-1753
            y = 1;                                # base year
            n = serialDay - 1;                    # num actual days since 1/1/1

            z4 = n / Date.DAYS_IN_4_YEARS;        # num 4-year blocks
            y += z4 * 4;
            n -= z4 * Date.DAYS_IN_4_YEARS;       # num days since y/1/1 (4)

            z = n / Date.DAYS_IN_NON_LEAP_YEAR;   # num whole years
            y += z;
            n -= z * Date.DAYS_IN_NON_LEAP_YEAR;  # num days since y/1/1 (1)

            if 4 == z and 0 == n:                 # last day in a leap year
                year      = y - 1;
                dayOfYear = Date.DAYS_IN_LEAP_YEAR;
            else:
                year      = y;
                dayOfYear = n + 1;
            return (year, dayOfYear)

    def isLeapYear(self, year):
        return 0 == year % 4 and (
            0 != year % 100 or 0 == year % 400 or year <= 1752)

    def dayOfYearToDayMonth(self, year, dayOfYear):
        if year == Date.YEAR_1752:
            daysThroughMonth = Date.y1752DaysThroughMonth
        elif self.isLeapYear(year):
            daysThroughMonth = Date.leapDaysThroughMonth
        else:
            daysThroughMonth = Date.normDaysThroughMonth

        m = 0
        while daysThroughMonth[m] < dayOfYear:
            m = m + 1

        d = dayOfYear - daysThroughMonth[m - 1]

        if (year == Date.YEAR_1752 and m == Date.SEPTEMBER and
            d >= Date.YEAR_1752_FIRST_MISSING_DAY):
            d += Date.YEAR_1752_NUM_MISSING_DAYS

        return (m,d)

    def to_string(self):
        serialDay = int(self.val['d_serialDate'])

        (year, dayOfYear) = self.serialToYearDate(serialDay)
        (month, day)      = self.dayOfYearToDayMonth(year, dayOfYear)

        return "%04d-%02d-%02d" % (year, month, day)

class DateTz:
    """Pretty printer for 'bdet_DateTz'"""
    def __init__(self,val):
        self.val = val

    def to_string(self):
        date = Date(self.val['d_localDate']).to_string()
        offset = self.val['d_offset']
        if (offset >= 0):
            return '%s +%d' % (date, offset)
        else:
            return '%s %d' % (date, offset)

class BslString:
    """Printer for 'bsl::string'.

    The pretty printer for 'bsl::string' ('bsl::basic_string<char>') uses the
    pretty printers 'ContainerBase' and 'StringImp'.  See the documentation
    below to interpret the printout.

        string = {
          mechanism = <BloombergLP::g_newDeleteAllocatorSingleton>,
          data = [size:11,capacity:19] "Hello there"
        }

    Note that while common pretty printers for 'std::string' will only dump
    the contents ("Hello there"), printing out the 'mechanism'
    ('bslma::Allocator*') helps detect bugs by which a member of a type might
    not be using the same allocator as the container.  The size and, to lesser
    extent, capacity and use of small string optimization can help detect other
    issues and do not add too much verbosity to the output.

    See also: 'BslStringImp', 'ContainerBase'
    """
    def __init__(self,val):
        self.val = val
        self.cbase = val.cast(val.type.items()[1][1].type)
        self.simp  = val.cast(val.type.items()[0][1].type)
        self.members = _createAllocatorList(self.cbase)
        self.members.append(('data', self.simp))

    def to_string(self):
        return "bsl::string"

    def children(self):
        return iter(self.members)

class BslVector:
    """Printer for 'bsl::vector<T,bsl::allocator<T>>'

    The pretty printer for specializations of 'bsl::vector<>' is implemented
    in terms of the 'ContainerBase' and 'VectorImp' pretty printers.

        vector = {
          alloc = <BloombergLP::g_newDeleteAllocatorSingleton>,
          data = [size:10,capacity:16] = {5, 5, 5, 5, 5, 5, 5, 5, 5, 5}
        }

    Note: There is no support for 'bsl::vector<bool>' printing.

    See also 'BslVectorImp'
    """
    def __init__(self, val):
        self.val     = val
        vimp         = val.cast(val.type.items()[0][1].type)
        self.members = _createAllocatorList(
                                     vimp.cast(vimp.type.items()[1][1].type))
        self.members.append(('data', vimp.cast(vimp.type.items()[0][1].type)))

    def to_string(self):
        return str(self.val.type)

    def children(self):
        return iter(self.members)


class BslMap:
    """Printer for a bsl::map<K,V>

    The implementation of 'bsl::map' uses type erasure to minimize the amount
    of code.  The type holds two members, the first one wraps the polymorphic
    allocator and comparator, while the second member is a generic RB-tree.

    Since the internal tree does not hold the information of what data is
    stored in the node, the pretty printer is forced to dump the contents of
    the map directly in this pretty printer, forcing the 'to_string' to dump
    all state other than the actual contents.
    """
    def __init__(self, val):
        self.val = val
        self.keyArg   = val.type.template_argument(0)
        self.valueArg = val.type.template_argument(1)

        self.valueType = gdb.lookup_type('bsl::pair<%s, %s >'
                                                        % (self.keyArg.const(),
                                                           self.valueArg))
        self.size     = val['d_tree']['d_numNodes']
        self.alloc    = (
            val['d_compAndAlloc']['d_pool']['d_pool']['d_mechanism'])
        self.sentinel = val['d_tree']['d_sentinel']

    def to_string(self):
        # Locally handle the printing the allocator or not
        return "map<%s,%s> [%s]" % (self.keyArg,
                                    self.valueArg,
                                    _sizeAndAllocator(self.size, self.alloc)
                                    )

    def display_hint(self):
        return 'map'

    def children(self):
        return keyValueIterator(PairTupleIterator(
            BslRbTreeIterator(self.valueType, self.sentinel)))

class BslSet:
    """Printer for a bsl::set

    The implementation of 'bsl::set' uses type erasure to minimize the amount
    of code.  The type holds two members, the first one wraps the polymorphic
    allocator and comparator, while the second member is a generic RB-tree.

    Since the internal tree does not hold the information of what data is
    stored in the node, the pretty printer is forced to dump the contents of
    the set directly in this pretty printer, forcing the 'to_string' to dump
    all state other than the actual contents.
    """
    def __init__(self, val):
        self.val       = val
        self.valueType = val.type.template_argument(0)
        self.nodeType  = gdb.lookup_type('BloombergLP::bslstl::TreeNode<%s>'
                                                              % self.valueType)

        self.size     = val['d_tree']['d_numNodes']
        self.alloc    = (
            val['d_compAndAlloc']['d_pool']['d_pool']['d_mechanism'])
        self.sentinel = val['d_tree']['d_sentinel']

    def to_string(self):
        return "set<%s> [%s]" % (self.valueType,
                                 _sizeAndAllocator(self.size, self.alloc))

    def display_hint(self):
        return 'array'

    def children(self):
        return valueIterator(BslRbTreeIterator(self.valueType, self.sentinel))

# TODO: add support for bslma-allocator parameter
class BslUnorderedMap:
    """Printer for a bsl::unordered_map<K,V>"""
    def __init__(self, val):
        self.impl     = val['d_impl']
        self.size     = int(self.impl['d_size'])
        self.capacity = int(self.impl['d_capacity'])

        self.keyArg   = val.type.template_argument(0)
        self.valueArg = val.type.template_argument(1)

        self.valueType = gdb.lookup_type('bsl::pair<%s, %s >'
                                                        % (self.keyArg.const(),
                                                           self.valueArg))

        anchor        = self.impl['d_anchor']
        self.buckets  = int(anchor['d_bucketArraySize'])
        self.listRoot = anchor['d_listRootAddress_p']

    def to_string(self):
        return "unordered_map<%s,%s> [size:%d,capacity:%d,buckets:%d]" % (
            self.keyArg, self.valueArg, self.size, self.capacity, self.buckets)

    def display_hint(self):
        return 'map'

    def children(self):
        return keyValueIterator(PairTupleIterator(
            HashTableIterator(self.valueType, self.listRoot)))

# TODO: add support for bslma-allocator parameter
class BslUnorderedSet:
    """Printer for a bsl::unordered_set<V>"""
    def __init__(self, val):
        self.impl     = val['d_impl']
        self.size     = int(self.impl['d_size'])
        self.capacity = int(self.impl['d_capacity'])

        self.valueType = val.type.template_argument(0)

        anchor        = self.impl['d_anchor']
        self.buckets  = int(anchor['d_bucketArraySize'])
        self.listRoot = anchor['d_listRootAddress_p']

    def to_string(self):
        return ("unordered_set<%s> [size:%d,capacity:%d,buckets:%d]"
                % (self.valueType, self.size, self.capacity, self.buckets))

    def display_hint(self):
        return 'array'

    def children(self):
        return valueIterator(HashTableIterator(self.valueType, self.listRoot))

class BslPair:
    """Pretty printer for 'bsl::pair'

    """
    def __init__(self, val):
        self.val = val
        self.members = [('first',  val['first']),
                        ('second', val['second'])]
    def to_string(self):
        return str(self.val.type)

    def children(self):
        return iter(self.members)

class BslAtomic:
    """Pretty printer for bsls::Atomic* types

    This will only print the internal value, whether a 32, 64 bit integer or
    a pointer.  In the case of a pointer, if you need to dereference it, the
    member storing the value is 'ptr.d_value.d_value'.

    Example outputs:

        BloombergLP::bsls::AtomicInt = 64
        BloombergLP::bsls::AtomicPointer<int> = 0x0
    """
    def __init__(self, val):
        self.val   = val
        self.value = val['d_value']['d_value']

    def to_int(self):
        """Return the value of this atomic value as 'int'"""
        return int(self.value)

    def to_string(self):
        return "%s = %s" % (self.val.type, self.value)

class BslSharedPtr:
    """Pretty printer for 'bsl::shared_ptr<TYPE>' and 'bsl::weak_ptr<TYPE>'

    This pretty printer will display the shared/weak pointer reference count
    and the value of the pointed object.  The format of the output will be

    """
    def __init__(self, val):
        self.val  = val
        self.type = val.type.template_argument(0)
        ptr = val['d_ptr_p']
        if ptr == 0:
            self.null   = True
        else:
            self.null = False
            ## adjusted shared count holds 2*count + X
            ##      where X == 1 if at least 1 weak ptr was created
            self.shared = BslAtomic(
                val['d_rep_p']['d_adjustedSharedCount']).to_int()
            self.shared = self.shared / 2
            ## adjusted weak count holds 2*count + X
            ##      where X == 1 if there are outstanding shared ptrs
            self.weak   = BslAtomic(
                val['d_rep_p']['d_adjustedWeakCount']).to_int()
            self.weak   = self.weak / 2
            self.members = [ ('*d_ptr_p', val['d_ptr_p'].dereference() )]

    def to_string(self):
        if self.null:
            return '[null]' % (self.type)
        else:
            return '%s [ref:%d,weak:%d]' % (self.val.type, self.shared,
                                            self.weak)

    def children(self):
        if self.null:
            return []
        else:
            return iter(self.members)

class BslmaManagedPtr:
    """Pretty printer for 'bslma::ManagedPtr<TYPE>'

    This pretty printer will print either "<NULL>" or the contents of the
    object pointed by the managed pointer.

    TODO: Detect whether the deleter is an allocator and print it if the
          configuration is set to print allocator pointers.
    """
    def __init__(self, val):
        self.val  = val
        self.type = val.type.template_argument(0)
        self.ptr = val['d_members']['d_obj_p']
        if (self.ptr == 0):
            self.null = True
        else:
            self.null = False
            self.ptr  = self.ptr.cast(self.type.pointer())

    def to_string(self):
        if (self.null):
            return 'ManagedPtr<%s> [null]' % (self.type)
        else:
            return 'ManagedPtr<%s> = %s' % (self.type, self.ptr.dereference())

###############################################################################
##  Commands and functions
###############################################################################
class BdeHelpCommand(gdb.Command):
    """This command will print help on BDE pretty printers"""
    def __init__(self):
        super(BdeHelpCommand, self).__init__("bde-help", gdb.COMMAND_SUPPORT)

    def invoke(self, arg, from_tty):
        args = gdb.string_to_argv(arg)
        if len(args) == 0:
            print __doc__
        elif len(args) == 1 and args[0] in docs:
            print docs[args[0]]
        else:
            print """
    Usage: bde-help [element]

        Prints the documentation for 'element'.

        bde-help            -- show documentation for the whole module
        bde-help BslString  -- show documentation for the BslString printer
"""

class BslShowAllocatorParameter(gdb.Parameter):
    """Control whether the bslma::Allocator is printed in each object.

    The allocator in use inside an object of container is an important piece of
    information, and printing the allocator can help debug issues where the
    allocator is not properly "injected" into the members of a type.  On the
    other hand, when debugging the logic of the application, printing the
    allocator for each member, which is by definition the same for all, can add
    noise and make it harder to read the data.
    """
    set_doc  = "Controls printing the bslma::Allocator in use"
    show_doc = "Display the bslma::Allocator in use"
    value    = True
    def __init__(self):
        super(BslShowAllocatorParameter,self).__init__('print bslma-allocator',
                                                       gdb.COMMAND_DATA,
                                                       gdb.PARAM_BOOLEAN)
    def get_set_string(self):
        if self.value:
            return "Print bslma::Allocator"
        else:
            return "Do not print bslma::Allocator"

    def get_show_string(self,svalue):
        return "Printing of bslma-allocator is %s." % ('on' if svalue else
                                                       'off')

class BslEclipseModeParameter(gdb.Parameter):
    """Control whether the containers are printed in raw mode.

    Eclipse requires the raw mode for processing container key/value pairs
    where as gdb prints the containers in a better format if key/values are
    alternated as ('key', key) and ('value', value).
    """
    set_doc  = "Controls printing containers in eclipse mode"
    show_doc = "Print containers in eclipse mode"
    value    = False
    def __init__(self):
        super(BslEclipseModeParameter,self).__init__('print bsl-eclipse',
                                                 gdb.COMMAND_DATA,
                                                 gdb.PARAM_BOOLEAN)
    def get_set_string(self):
        if self.value:
            return "Printing BDE containers in eclipse mode"
        else:
            return "Not printing BDE containers in eclipse mode"

    def get_show_string(self,svalue):
        return "Printing containers in eclipse mode is %s." % ('on' if svalue
                                                               else 'off')


###############################################################################
##
##  Create and register the pretty printers
##  ---------------------------------------
##
## Register the printers in gdb using the gdb.printing module
##
###############################################################################
def init_globals():
    ## Init globals
    try:
        global boolType
        boolType = gdb.lookup_type('bool')

        global docs
        docs = { }

        global pp
        pp = gdb.printing.RegexpCollectionPrettyPrinter("BDE")
    except:
        pass

def add_printer(name, re, klass):
    docs[name] = klass.__doc__
    docs[klass.__name__] = klass.__doc__
    pp.add_printer(name, re, klass)

def build_pretty_printer():
    if boolType is None:
        init_globals()

    add_printer('IPv4Address', '^BloombergLP::bteso_IPv4Address$', IPv4Address)
    add_printer('NullableValue',
                'BloombergLP::bdeut_NullableValue<.*>',
                Nullable)
    add_printer('bdet_Time', 'BloombergLP::bdet_Time', Time);
    add_printer('bdet_Date', '^BloombergLP::bdet_Date$', Date);
    add_printer('bdet_DateTz', '^BloombergLP::bdet_DateTz$', DateTz);

    add_printer('ContainerBase',
                '^BloombergLP::bslalg::ContainerBase<bsl::allocator<.*> >$',
                ContainerBaseBslma)

    add_printer('StringImp', '^bsl::String_Imp<char,.*>$', BslStringImp)
    add_printer('string', '^bsl::basic_string<char,.*>$', BslString)

    add_printer('VectorImp', '^bsl::Vector_ImpBase<.*>', BslVectorImp)
    add_printer('vector', '^bsl::vector<.*>$', BslVector)

    add_printer('map', '^bsl::map<.*>$', BslMap)
    add_printer('set', '^bsl::set<.*>$', BslSet)

    add_printer('unordered_map', '^bsl::unordered_map<.*>$', BslUnorderedMap)
    add_printer('unordered_set', '^bsl::unordered_set<.*>$', BslUnorderedSet)

    add_printer('pair', '^bsl::pair<.*>$', BslPair)

    add_printer('atomic', '^BloombergLP::bsls::Atomic.*$', BslAtomic)

    add_printer('shared_ptr', '^bsl::shared_ptr<.*>$', BslSharedPtr)
    add_printer('weak_ptr', '^bsl::weak_ptr<.*>$', BslSharedPtr)
    add_printer('ManagedPtr',
                '^BloombergLP::bslma::ManagedPtr<.*>$',
                BslmaManagedPtr)

    #add_printer('catchall', '.*', CatchAll)
    return pp

def reload():
    ## Create the commands
    BslShowAllocatorParameter ()
    BdeHelpCommand ()
    BslEclipseModeParameter ()

    ## Remove the pretty printer if it exists
    for pp in gdb.pretty_printers:
        if (pp.name == 'BDE'):
            gdb.pretty_printers.remove(pp)
            break

    ## Create the new pretty printer
    gdb.printing.register_pretty_printer(gdb.current_objfile(),
                                         build_pretty_printer())

reload()

# (gdb) python execfile(\
#           "/bbshr/bde/bde-oss-tools/contrib/gdb-printers/bde_printer.py")
