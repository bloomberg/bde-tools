"""
   GDB pretty printer support for BDE components

   This module provides a set of pretty printers to load into gdb for debugging
   code using BDE (http://github.com/bloomberg/bde) components.

   This is a work in progress, more printers will be added as needed.

   Authors: David Rodriguez Ibeas <dribeas@bloomberg.net>
            Evgeny Yakimov        <eyakimov@bloomberg.net>
            Hyman Rosen           <hrosen4@bloomberg.net>

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

    string-address    Controls whether string buffer address is printed

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
"""

#  General design considerations
#  -----------------------------
#   Pretty printers should focus on the useful information for the developer
#   that is debugging the application.  What is useful for one developer might
#   be too verbose for another and not enough for a third one.  Unless
#   otherwise noted the provided pretty printers will reformat the available
#   information but avoid hiding data from the developer.  The implication is
#   that the output might be slightly verbose (the 'bslma::Allocator' pointer
#   in containers is printed always, the size and capacity for 'bsl::string' is
#   printed...).  Other existing pretty printers (for example for the standard
#   library provided with gcc) will omit details and focus on the data.
#
#   The format used for output has been considered for a high information
#   density given that it will print more things than needed by most users.
#   The description of the format for each one of the pretty printers is
#   documented below and does not reflect the layout of the C++ types that are
#   being printed.

import re
import string
import sys
import gdb
import gdb.printing

###############################################################################
# Private Types and Helpers
###############################################################################

global docs
docs = { }

global pp
pp = None

##  Helpers controlling the printout based on printer options
def _createAllocatorList(cbase):
    """Create a list with the allocator information if 'print bslma-allocator'
       is set or empty otherwise.
    """
    printAllocator = gdb.parameter('print bslma-allocator')
    return [] if not printAllocator else [('alloc',cbase)]

def _optionalAllocator(allocator, prefix = ',', suffix = ''):
    printalloc = gdb.parameter('print bslma-allocator')
    return '%salloc:%s%s' % (prefix, allocator, suffix) if printalloc else ''

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

def stringAddress(arg):
    char_ptr_type = gdb.lookup_type('unsigned char').pointer()
    c_str = arg.cast(char_ptr_type)
    return '0x%x ' % c_str if gdb.parameter('print string-address') else ''

def stringRep(arg, length):
    print_len = gdb.parameter("print elements")
    if not print_len or print_len + 4 > length:
        print_len = length
    print_str = ''
    char_ptr_type = gdb.lookup_type('unsigned char').pointer()
    c_str = arg.cast(char_ptr_type)
    for i in xrange(print_len):
        ci = (c_str + i).dereference()
        cc = chr(ci)
        if cc in string.printable:
            print_str += cc
        else:
            print_str += "\{0:03o}".format(int(ci))
    if print_len < length: print_str += '...'
    return print_str

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


class BslStringImp:
    """Pretty printer for 'bsl::String_Imp<char>'

    The implementation of 'bsl::string' ('bsl::basic_string<>' template) uses a
    base template 'bsl::String_Imp<>' to handle the actual contents.  This
    implementation uses a small string optimization with an internal buffer
    that depends on the architecture.  The pretty printer for this type will
    print a compact representation of the available information, encoding in
    the capitalization of the message whether the current object is using the
    small buffer ('size') or the dynamically allocated large buffer ('Size').
    The 'print string-address' parameter controls whether the address of the
    string buffer is printed.

        # With print string-address on
        data = 0x0x8051074 [size:5,capacity:19] "short"
        # With print string-address off
        data = [Size:24,capacity:34] "This is a long string!!!"

    The size of the internal buffer is detected at runtime.

    Note that the pretty printer only handles narrow character strings,
    'bsl::string', and not wide character strings 'bsl::wstring' or any other
    specialization of the 'bsl::basic_string<>' template.

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

    If 'print elements' is set, the value will be used to limit the number of
    characters printed, and the string will terminate with a "..." indicating
    more characters are present.  Non-printable characters are written out as a
    backslash and three octal digits.

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
            str = '%s[%s:%d,capacity:%d] "%s"' % (
                                           stringAddress(self.buffer),
                                           'size' if self.isShort else 'Size',
                                           self.length,
                                           self.capacity,
                                           stringRep(self.buffer, self.length))
        else:
            if self.isShort:
                str = '[DESTROYED, small buffer value]: %s' % self.buffer
            else:
                str = '[DESTROYED] %s' % self.buffer
        return str

class BslVectorImp:
    """Printer for 'bsl::vectorBase<T>' specializations.

    This pretty printer handles printing instances of the
    'bsl::vectorBase<>' template used to hold the contents of
    'bsl::vector<>'.  The printer will dump the size and capacity of the
    object followed by the sequence of values in the sequence.

        [size:10,capacity:16] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}

    Note: This is not intended for direct use
    """
    def __init__(self, val):
        self.val = val
        self.begin    = val['d_dataBegin_p']
        self.end      = val['d_dataEnd_p']
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
        self.iter = iter

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
        self.iter = iter

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
        self.iter = iter

    def __iter__(self):
        return self

    def next(self):
        value = self.iter.next()
        return ('value',value)

class RawKeyValueIterator:
    """This iterator returns a (str(key),value) tuple from an iterator."""
    def __init__(self,iter):
        self.iter = iter

    def __iter__(self):
        return self

    def next(self):
        next = self.iter.next()
        return (str(next[0]),next[1])

class RawValueIterator:
    """This iterator returns a (str(value),value) tuple from an iterator."""
    def __init__(self,iter):
        self.iter = iter

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
    """Pretty printer for 'bdlb::NullableValue<T>'

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
            self.members = _createAllocatorList(alloc)

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
    """Pretty printer for 'bdlt::Time'

    The value is shown in 'hh:mm:ss.xxx' format.
    """
    def __init__(self, val):
        self.val = val

    @classmethod
    def toHMmS(cls, value):
        milliseconds  = value % 1000
        value        /= 1000
        seconds       = value % 60
        value        /= 60
        minutes       = value % 60
        value        /= 60
        hours         = value

        return "%02d:%02d:%02d.%03d" % (hours, minutes, seconds, milliseconds)

    @classmethod
    def toHMuS(cls, value):
        microseconds  = value % 1000000
        value        /= 1000000
        seconds       = value % 60
        value        /= 60
        minutes       = value % 60
        value        /= 60
        hours         = value

        return "%02d:%02d:%02d.%06d" % (hours, minutes, seconds, microseconds)

    def to_string(self):
        us = long(self.val['d_value'])
        mask = 0x4000000000
        if (us < mask):
            return "invalid time value %d" % us
        return Time.toHMuS(us & ~mask)

class Tz:
    """Utility to format a time zone offset."""
    @classmethod
    def toHM(cls, offset):
        sign = '-' if offset < 0 else '+'
        if offset < 0:
            offset = -offset
            sign = '-'
        else:
            sign = '+'
        return '%s%02d:%02d' % (sign, offset / 60, offset % 60)

class TimeTz:
    """Pretty printer for 'bdlt::TimeTz'

    The value is shown in 'hh:mm:ss.xxx+hh:mm' format.
    """
    def __init__(self,val):
        self.val = val

    def to_string(self):
        time = Time(self.val['d_localTime']).to_string()
        return '%s%s' % (time, Tz.toHM(self.val['d_offset']))

class Date:
    """Pretty printer for 'bdlt::Date'

    The value is shown in 'YYYYY-MM-DD' format.
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

    @classmethod
    def serialToYearDate(cls, serialDay):
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
            y = 1                                 # base year
            n = serialDay - 1                     # num actual days since 1/1/1

            z4 = n / Date.DAYS_IN_4_YEARS         # num 4-year blocks
            y += z4 * 4
            n -= z4 * Date.DAYS_IN_4_YEARS        # num days since y/1/1 (4)

            z = n / Date.DAYS_IN_NON_LEAP_YEAR    # num whole years
            y += z
            n -= z * Date.DAYS_IN_NON_LEAP_YEAR   # num days since y/1/1 (1)

            if 4 == z and 0 == n:                 # last day in a leap year
                year      = y - 1
                dayOfYear = Date.DAYS_IN_LEAP_YEAR
            else:
                year      = y
                dayOfYear = n + 1
            return (year, dayOfYear)

    @classmethod
    def isLeapYear(cls, year):
        return 0 == year % 4 and (
            0 != year % 100 or 0 == year % 400 or year <= 1752)

    @classmethod
    def dayOfYearToDayMonth(cls, year, dayOfYear):
        if year == Date.YEAR_1752:
            daysThroughMonth = Date.y1752DaysThroughMonth
        elif Date.isLeapYear(year):
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

    @classmethod
    def toYMD(cls, serialDay):
        (year, dayOfYear) = Date.serialToYearDate(serialDay)
        (month, day)      = Date.dayOfYearToDayMonth(year, dayOfYear)

        return "%04d-%02d-%02d" % (year, month, day)

    def to_string(self):
        return Date.toYMD(self.val['d_serialDate'])

class DateTz:
    """Pretty printer for 'bdlt::DateTz'

    The value is shown in 'YYYYY-MM-DDT00+hh:mm' format.
    """
    def __init__(self,val):
        self.val = val

    def to_string(self):
        date = Date(self.val['d_localDate']).to_string()
        return '%sT00%s' % (date, Tz.toHM(self.val['d_offset']))

class Datetime:
    """Pretty printer for 'bdlt::Datetime'
    
    The value is shown in 'YYYYY-MM-DDTHH:MM:SS.SSSSSS' format.
    """
    REP_MASK  = 0x08000000000000000
    DATE_MASK = 0x0ffffffe000000000
    TIME_MASK = 0x00000001fffffffff
    MASK_32   = 0x000000000ffffffff
    SHIFT_32  = 32
    TIME_BITS = 37

    def __init__(self,val):
        self.val = val

    def to_string(self):
        value = long(self.val['d_value'])
        if value < 0:
            value += 2 ** 64
        invalid = (value & Datetime.REP_MASK) == 0
        if invalid:
            if sys.byteorder == "little":
                days = (value & Datetime.MASK_32) - 1
                milliseconds = value >> Datetime.SHIFT_32
            else:
                days = (value >> Datetime.SHIFT_32) - 1
                milliseconds = value & Datetime.MASK_32
            value = (days << Datetime.TIME_BITS) | (1000 * milliseconds)
        else:
            value ^= Datetime.REP_MASK
        date = Date.toYMD((value >> Datetime.TIME_BITS) + 1)
        time = Time.toHMuS(value & Datetime.TIME_MASK)

        return "%s%sT%s" % (("[invalid]" if invalid else ""), date, time)

class DatetimeTz:
    """Pretty printer for 'bdlt::DatetimeTz'
    
    The value is shown in 'YYYYY-MM-DDThh:mm:ss.ssssss+hh:mm' format.
    """
    def __init__(self,val):
        self.val = val

    def to_string(self):
        datetime = Datetime(self.val['d_localDatetime']).to_string()
        return '%s%s' % (datetime, Tz.toHM(self.val['d_offset']))

class BslString:
    """Printer for 'bsl::string'.

    The pretty printer for 'bsl::string' ('bsl::basic_string<char>') uses the
    pretty printer for 'StringImp'.  See the documentation below to interpret
    the printout.

        string = {
          alloc = 0x804fdf0 <BloombergLP::g_newDeleteAllocatorSingleton>,
          data = [size:11,capacity:19] "Hello there"
        }

    Note that while common pretty printers for 'std::string' will only dump
    the contents ("Hello there"), printing out the allocator
    ('bslma::Allocator*') helps detect bugs by which a member of a type might
    not be using the same allocator as the container.  The size and, to lesser
    extent, capacity and use of small string optimization can help detect other
    issues and do not add too much verbosity to the output.

    See also: 'BslStringImp'
    """
    def __init__(self,val):
        self.val = val
        self.alloc   = val['d_allocator']['d_mechanism']
        self.simp  = val.cast(val.type.items()[0][1].type)
        self.members = _createAllocatorList(self.alloc)
        self.members.append(('data', self.simp))

    def to_string(self):
        return "bsl::string"

    def children(self):
        return iter(self.members)

class StringRefData:
    """Printer for bslstl::StringRef implementation data

    The format of the output is [length:6] "abcdef"
    """
    def __init__(self, val):
        self.val = val

    def to_string(self):
        length = self.val['d_end_p'] - self.val['d_begin_p']
        buffer = self.val['d_begin_p']
        return '%s[length:%d] "%s"' % (stringAddress(buffer),
                                       length,
                                       stringRep(buffer, length))

class StringRef:
    """Printer for bslstl::StringRef

    The format of the output is bslstl::StringRef = {data = [length:2] "ab"}
    """
    def __init__(self, val):
        self.val = val
        self.imp = val.cast(val.type.items()[0][1].type)
        self.members = [('data', self.imp)]

    def to_string(self):
        return "bslstl::StringRef";

    def children(self):
        return iter(self.members)

class BslVector:
    """Printer for 'bsl::vector<T,bsl::allocator<T>>'

    The pretty printer for specializations of 'bsl::vector<>' is implemented
    in terms of the 'VectorImp' pretty printer.

        vector = {
          alloc = 0x804fdf0 <BloombergLP::g_newDeleteAllocatorSingleton>,
          data = [size:10,capacity:16] = {5, 5, 5, 5, 5, 5, 5, 5, 5, 5}
        }

    See also 'BslVectorImp'
    """
    def __init__(self, val):
        self.val     = val
        self.alloc   = val['d_allocator']['d_mechanism']
        self.vimp    = val.cast(val.type.items()[0][1].type)
        self.members = _createAllocatorList(self.alloc)
        self.members.append(('data', self.vimp))

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
        return "map<%s,%s> [size:%d%s]" % (self.keyArg,
                                           self.valueArg,
                                           self.size,
                                           _optionalAllocator(self.alloc))

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
        self.val = val
        self.valueType = val.type.template_argument(0)
        self.nodeType = gdb.lookup_type(
            'BloombergLP::bslstl::TreeNode<%s>' % self.valueType)

        self.size = val['d_tree']['d_numNodes']
        self.alloc = val['d_compAndAlloc']['d_pool']['d_pool']['d_mechanism']
        self.sentinel = val['d_tree']['d_sentinel']

    def to_string(self):
        # Locally handle the printing the allocator or not
        return "set<%s> [size:%d%s]" % (self.valueType,
                                        self.size,
                                        _optionalAllocator(self.alloc))

    def display_hint(self):
        return 'array'

    def children(self):
        return valueIterator(BslRbTreeIterator(self.valueType, self.sentinel))

class BslUnorderedMap:
    """Printer for a bsl::unordered_map<K,V>"""
    def __init__(self, val):
        self.impl = val['d_impl']
        self.size = int(self.impl['d_size'])
        self.capacity = int(self.impl['d_capacity'])
        self.alloc = (self.impl['d_parameters']['d_nodeFactory']['d_pool']
                               ['d_mechanism'])

        self.keyArg   = val.type.template_argument(0)
        self.valueArg = val.type.template_argument(1)

        self.valueType = gdb.lookup_type('bsl::pair<%s, %s >'
                                                        % (self.keyArg.const(),
                                                           self.valueArg))

        anchor        = self.impl['d_anchor']
        self.buckets  = int(anchor['d_bucketArraySize'])
        self.listRoot = anchor['d_listRootAddress_p']

    def to_string(self):
        return "unordered_map<%s,%s> [size:%d,capacity:%d,buckets:%d%s]" % (
            self.keyArg, self.valueArg, self.size, self.capacity, self.buckets,
            _optionalAllocator(self.alloc))

    def display_hint(self):
        return 'map'

    def children(self):
        return keyValueIterator(PairTupleIterator(
            HashTableIterator(self.valueType, self.listRoot)))

class BslUnorderedSet:
    """Printer for a bsl::unordered_set<V>"""
    def __init__(self, val):
        self.impl = val['d_impl']
        self.size = int(self.impl['d_size'])
        self.capacity = int(self.impl['d_capacity'])
        self.alloc = (self.impl['d_parameters']['d_nodeFactory']['d_pool']
                               ['d_mechanism'])

        self.valueType = val.type.template_argument(0)

        anchor = self.impl['d_anchor']
        self.buckets = int(anchor['d_bucketArraySize'])
        self.listRoot = anchor['d_listRootAddress_p']

    def to_string(self):
        return ("unordered_set<%s> [size:%d,capacity:%d,buckets:%d%s]"
                % (self.valueType, self.size, self.capacity, self.buckets,
                   _optionalAllocator(self.alloc)))

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
    bsl::shared_ptr<type> [ref:n,weak:n] = {*d_ptr_p = ...} (and the same for
    bsl::weak_ptr).  If the pointer is null, the data portion looks like
    {d_ptr_p = 0x0} instead.

    """
    def __init__(self, val):
        self.val  = val
        self.type = val.type.template_argument(0)
        ptr = val['d_ptr_p']
        rep = val['d_rep_p']
        if rep == 0:
            self.shared = 0
            self.weak = 0
        else:
            # adjusted shared count holds 2*count + X
            # where X == 1 if at least 1 weak ptr was created
            self.shared = BslAtomic(rep['d_adjustedSharedCount']).to_int() / 2
            # adjusted weak count holds 2*count + X
            # where X == 1 if there are outstanding shared ptrs
            self.weak = BslAtomic(rep['d_adjustedWeakCount']).to_int() / 2
        if ptr == 0:
            self.members = [('d_ptr_p', ptr)]
        else:
            self.members = [('*d_ptr_p', ptr.dereference())]

    def to_string(self):
        return '%s [ref:%d,weak:%d]' % (self.val.type, self.shared, self.weak)

    def children(self):
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
        global docs
        args = gdb.string_to_argv(arg)
        if len(args) == 0:
            print(__doc__)
            print("The following pretty-printers are documented:")
            for d in sorted(docs.keys()):
                print(d)
        elif len(args) == 1 and args[0] in docs:
            print(docs[args[0]])
        else:
            print(
"""
    Usage: bde-help [element]

        Prints the documentation for 'element'.

        bde-help            -- show documentation for the whole module
        bde-help BslString  -- show documentation for the BslString printer
"""
            )

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

class BslStringAddressParameter(gdb.Parameter):
    """Control whether string buffer addresses are printed.
    """
    set_doc  = "Controls printing string buffer address"
    show_doc = "Print string buffer address"
    value    = False
    def __init__(self):
        super(BslStringAddressParameter,self).__init__('print string-address',
                                                       gdb.COMMAND_DATA,
                                                       gdb.PARAM_BOOLEAN)
    def get_set_string(self):
        if self.value:
            return "Printing string buffer addresses"
        else:
            return "Not printing string buffer addresses"

    def get_show_string(self,svalue):
        return "Printing string buffer addresses is %s." % ('on' if svalue
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
        global docs
        docs = { }
        global pp
        pp = gdb.printing.RegexpCollectionPrettyPrinter("BDE")
    except:
        pass

def add_printer(name, re, klass):
    global docs
    docs[name] = klass.__doc__
    # docs[klass.__name__] = klass.__doc__
    global pp
    pp.add_printer(name, re, klass)

def build_pretty_printer():
    add_printer('bteso_IPv4Address', '^BloombergLP::bteso_IPv4Address$',
                IPv4Address)
    add_printer('bdlb::NullableValue', 'BloombergLP::bdlb::NullableValue<.*>',
                Nullable)

    add_printer('bdlt::Date', '^BloombergLP::bdlt::Date$', Date)
    add_printer('bdlt::DateTz', '^BloombergLP::bdlt::DateTz$', DateTz)
    add_printer('bdlt::Datetime', '^BloombergLP::bdlt::Datetime$', Datetime)
    add_printer('bdlt::DatetimeTz', '^BloombergLP::bdlt::DatetimeTz$',
                DatetimeTz)
    add_printer('bdlt::Time', '^BloombergLP::bdlt::Time$', Time)
    add_printer('bdlt::TimeTz', '^BloombergLP::bdlt::TimeTz$', TimeTz)

    add_printer('string', '^bsl::basic_string<char,.*>$', BslString)
    add_printer('(internal)StringImp', '^bsl::String_Imp<char,.*>$',
                BslStringImp)
    add_printer('bslstl::StringRef',
                '^BloombergLP::bslstl::StringRefImp<char>$',
                StringRef)
    add_printer('(internal)StringRefData',
                '^BloombergLP::bslstl::StringRefData<char>$',
                StringRefData)

    add_printer('(internal)VectorImp', '^bsl::vectorBase<.*>',
                BslVectorImp)
    add_printer('vector', '^bsl::vector<.*>$', BslVector)

    add_printer('map', '^bsl::map<.*>$', BslMap)
    add_printer('set', '^bsl::set<.*>$', BslSet)

    add_printer('unordered_map', '^bsl::unordered_map<.*>$', BslUnorderedMap)
    add_printer('unordered_set', '^bsl::unordered_set<.*>$', BslUnorderedSet)

    add_printer('pair', '^bsl::pair<.*>$', BslPair)

    add_printer('atomic', '^BloombergLP::bsls::Atomic.*$', BslAtomic)

    add_printer('shared_ptr', '^bsl::shared_ptr<.*>$', BslSharedPtr)
    add_printer('weak_ptr', '^bsl::weak_ptr<.*>$', BslSharedPtr)
    add_printer('bslma::ManagedPtr', '^BloombergLP::bslma::ManagedPtr<.*>$',
                BslmaManagedPtr)

    #add_printer('catchall', '.*', CatchAll)
    global pp
    return pp

def reload():
    ## Create the commands
    init_globals()
    BslShowAllocatorParameter ()
    BdeHelpCommand ()
    BslEclipseModeParameter ()
    BslStringAddressParameter ()

    ## Remove the pretty printer if it exists
    for printer in gdb.pretty_printers:
        if (printer.name == 'BDE'):
            gdb.pretty_printers.remove(printer)
            break

    ## Create the new pretty printer
    gdb.printing.register_pretty_printer(gdb.current_objfile(),
                                         build_pretty_printer())

reload()

# (gdb) python execfile(\
#           "/bb/bde/bbshr/bde-tools/contrib/gdb-printers/bde_printer.py")
