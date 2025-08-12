"""
GDB pretty printer support for BDE components

This module provides a comprehensive set of pretty printers to load into gdb
for debugging code using BDE (http://github.com/bloomberg/bde) components.

This module includes printers for containers (vector, map, set, unordered_map,
unordered_set), strings, smart pointers, time/date types, variant types,
nullable values, atomic types, and decimal types.

Configuration options
---------------------
These settings configure some of the behavior of the pretty printer to
improve access to different elements in the underlying data.

    (gdb) set print bslma-allocator on

Setting           Meaning
---------------   -----------------------------------------------------
bslma-allocator   Controls whether the bslma::Allocator* is printed

string-address    Controls whether string buffer address is printed

Usage
-----
To use the pretty printers load the script into gdb, either manually
through:

    (gdb) source /path/to/this/folder/gdbinit

or automatically at start up.  See the gdb documentation on how to setup
automatic loading of pretty printers.

You can list, enable or disable pretty printers by using the gdb commands:

    (gdb) info    pretty-printer
    (gdb) disable pretty-printer global BDE;vector
    (gdb) enable  pretty-printer global BDE

Additionally, you can ignore the pretty printer for a single 'print'
command by running it in "raw" mode:

    (gdb) print /r container

Acknowledgements
----------------
Thank you to the following people for creating the initial version of this
module:
    David Rodriguez Ibeas
    Evgeny Yakimov
    Hyman Rosen


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
docs = {}

global pp
pp = None


##  Helpers controlling the printout based on printer options
def _allocatorResource(val):
    for resource in ["d_resource", "_M_resource"]:
        try:
            return val[resource]
        except:
            pass


def _allocatorDict(alloc):
    """Return a dictionary containing an allocator field if allocator printing
    is enabled and an empty dictionary otherwise."""
    return {"alloc": alloc} if gdb.parameter("print bslma-allocator") else {}


def _optionalAllocator(alloc, prefix=",", suffix=""):
    printalloc = gdb.parameter("print bslma-allocator")
    return f"{prefix}alloc:{alloc}{suffix}" if printalloc else ""


def stringAddress(arg):
    char_ptr_type = gdb.lookup_type("unsigned char").pointer()
    c_str = arg.cast(char_ptr_type)
    return f"0x{c_str:x} " if gdb.parameter("print string-address") else ""


def stringRep(arg, length):
    print_len = gdb.parameter("print elements")
    if not print_len or print_len + 4 > length:
        print_len = length
    print_str = ""
    char_ptr_type = gdb.lookup_type("unsigned char").pointer()
    c_str = arg.cast(char_ptr_type)
    for i in range(print_len):
        ci = (c_str + i).dereference()
        cc = chr(ci)
        if cc in string.printable:
            print_str += cc
        else:
            print_str += "\\{0:03o}".format(int(ci))
    if print_len < length:
        print_str += "..."
    return print_str


def hasMember(obj, memb):
    try:
        obj[memb]
    except gdb.error:
        return False
    return True


def getBaseType(val, index):
    """Return the type of base class number `index` of the type of the value
    `val`.  If no such base exists, return `None`"""
    try:
        return val.type.items()[index][1].type
    except:
        pass


def replace_template(text, pattern, replacement):
    """Replace all occurrences of the template type name adhering to the
    specified `pattern` with the specified `replacement` in the specified
    `text`.  Remove a trailing comma if `replacement` is empty.  The behavior
    is undefined unless `pattern` contains a `<` character."""

    assert "<" in pattern

    pattern = re.compile(pattern)
    result = ""
    i = 0

    while i < len(text):
        match = pattern.search(text, i)
        if not match:
            result += text[i:]
            break

        start = match.start()

        result += text[i:start]
        result += match.expand(replacement)

        # Move i past the matched template (handle nested < >)
        i = match.end()
        depth = 1
        while i < len(text) and depth > 0:
            if text[i] == "<":
                depth += 1
            elif text[i] == ">":
                depth -= 1
            i += 1

        # Remove trailing ", " only we're removing the template
        if len(replacement) == 0:
            trailing = re.match(r"\s*,\s*", text[i:])
            if trailing:
                i += trailing.end()

    return result.strip()


def simplifyTypeName(typeName):
    """Simplify the specified `typeName` by removing BloombergLP:: prefix,
    bsl::allocator template parameter, and handle common typedefs like
    bsl::string, bsl::wstring, etc."""

    typeName = str(typeName).replace("BloombergLP::", "")
    typeName = replace_template(typeName, "bsl::allocator<", "")
    typeName = replace_template(typeName, r"(std|bsl)::char_traits<", "")
    typeName = replace_template(typeName, r"(std|bsl)::basic_string(_view)?<char", r"\1::string\2")
    typeName = replace_template(typeName, r"(std|bsl)::basic_string(_view)?<wchar_t", r"\1::wstring\2")
    typeName = replace_template(
        typeName, r"bslstl::StringRef<char", "bslstl::StringRef"
    )
    typeName = replace_template(
        typeName, r"bslstl::StringRef<wchar_t", "bslstl::StringRefWide"
    )
    typeName = re.sub(r",?\s+>", ">", typeName)
    return typeName


## Debug catch all pretty printer
class CatchAll:
    """Not a pretty printer

    This type complies with the pretty printer interface, but will open an
    interactive python shell with the information available to the printer for
    debugging and testing purposes.
    """

    def __init__(self, val):
        """Store the gdb value in this object and open an interactive shell"""
        self.val = val
        import code

        code.interact(local=locals())

    def to_string(self):
        import code

        code.interact(local=locals())
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

    def __init__(self, val):
        """Precalculate the data needed to later print the string"""
        self.val = val
        length = val["d_length"]
        if str(length) == "4294967295":
            self.destroyed = True
            self.length = int(-1)
        else:
            self.destroyed = False
            self.length = int(val["d_length"])
        self.capacity = int(val["d_capacity"])
        short = val["d_short"]
        self.isShort = self.capacity < short.type.sizeof
        self.buffer = short["d_data"]["d_buffer"] if self.isShort else val["d_start_p"]

    def to_string(self):
        """Format the string"""
        str = None
        if not self.destroyed:
            str = (
                f"{stringAddress(self.buffer)}"
                f'[{"size" if self.isShort else "Size"}:{self.length},capacity:{self.capacity}]'
                f' "{stringRep(self.buffer, self.length)}"'
            )
        else:
            if self.isShort:
                str = f"[DESTROYED, small buffer value]: {self.buffer}"
            else:
                str = f"[DESTROYED] {self.buffer}"
        return str


class BslVectorImp:
    """Printer for 'bsl::vectorBase<T>' specializations.

    This pretty printer handles printing instances of the
    'bsl::vectorBase<>' template used to hold the contents of
    'bsl::vector<>'.  The printer will dump the size and capacity of the
    object and have children showing the elements.

        [size:10,capacity:16]

    Note: This is not intended for direct use
    """

    def __init__(self, val):
        self.val = val
        self.begin = val["d_dataBegin_p"]
        self.end = val["d_dataEnd_p"]
        self.size = int(self.end - self.begin)
        self.capacity = int(val["d_capacity"])

    def to_string(self):
        return f"[size:{self.size},capacity:{self.capacity}]"

    def display_hint(self):
        return "map"

    def children(self):
        class VectorContentsIterator:
            """Iterator over the contents of the vector"""

            def __init__(s, begin, end):
                s.end = end
                s.current = begin

            def __iter__(s):
                return s

            def __next__(s):
                if s.current == s.end:
                    raise StopIteration

                value = s.current.dereference()
                s.current += 1
                return value

            next = __next__

        return ValueIterator(VectorContentsIterator(self.begin, self.end))


def getNodeValue(node, type):
    # clang optimizes out TreeNode and BidirectionalNode even in debug builds.
    # Try to work around it by raw memory access.
    derivedPtr = node + 1

    # align pointer to self.valueType alignment
    off = int(str(derivedPtr), 16) & (type.alignof - 1)
    if off != 0:
        derivedPtr = (
            derivedPtr.cast(gdb.lookup_type("char").pointer()) + type.alignof - off
        )

    derivedPtr = derivedPtr.reinterpret_cast(type.pointer())

    return derivedPtr.dereference()


class BslRbTreeIterator:
    """Helper class to produce iterations over a RB-tree

    This is **not** a pretty printer, but a helper class to aid in the
    implementation of pretty printers for sorted associative containers using
    RB-Trees as underlying data structure.
    """

    def __init__(self, type, sentinel):
        self.sentinel = sentinel
        self.current = sentinel["d_right_p"]
        try:
            self.nodeType = gdb.lookup_type(f"BloombergLP::bslstl::TreeNode<{type}>")
        except gdb.error:
            self.valueType = type

    def value(self):
        if hasattr(self, "nodeType"):
            treeNode = self.current.dereference().cast(self.nodeType)
            return treeNode["d_value"]
        else:
            return getNodeValue(self.current, self.valueType)

    def __iter__(self):
        return self

    def __next__(self):
        if self.current == self.sentinel.address:
            raise StopIteration
        value = self.value()
        self.current = self.nextNode(self.current)
        return value

    next = __next__

    def followPointer(self, pointer, name):
        """Follow the pointer specified by 'name' in the specified 'object'.

        This function implements the equivalent in C++ of:
            return pointer->name & ~1
        """
        np = pointer.dereference()[name]
        npi = np.cast(gdb.lookup_type("long long"))
        if npi & 1:
            np = gdb.Value(npi & ~1).reinterpret_cast(np.type)
        return np

    def nextNode(self, pointer):
        if pointer["d_right_p"] != 0:
            pointer = self.followPointer(pointer, "d_right_p")
            l = self.followPointer(pointer, "d_left_p")
            while not l == 0:
                pointer = l
                l = self.followPointer(pointer, "d_left_p")
        else:
            p = self.followPointer(pointer, "d_parentWithColor_p")
            while (
                p != self.sentinel.address
                and self.followPointer(p, "d_right_p") == pointer
            ):
                pointer = p
                p = self.followPointer(p, "d_parentWithColor_p")
            pointer = p
        return pointer


class HashTableIterator:
    """Helper class to produce iterations over a hash table"""

    def __init__(self, type, sentinel):
        self.current = sentinel
        try:
            self.nodeType = gdb.lookup_type(
                f"BloombergLP::bslalg::BidirectionalNode<{type}>"
            )
        except gdb.error:
            self.valueType = type

    def value(self):
        if hasattr(self, "nodeType"):
            node = self.current.dereference().cast(self.nodeType)
            return node["d_value"]
        else:
            return getNodeValue(self.current, self.valueType)

    def __iter__(self):
        return self

    def __next__(self):
        if self.current == 0:
            raise StopIteration
        value = self.value()
        self.current = self.current["d_next_p"]
        return value

    next = __next__


class PairTupleIterator:
    """Helper class to convert bsl::pair to a tuple as an iterator"""

    def __init__(self, iter):
        self.iter = iter

    def __iter__(self):
        return self

    def __next__(self):
        nextPair = self.iter.next()
        return (nextPair["first"], nextPair["second"])

    next = __next__


class KeyValueIterator:
    """This iterator converts an iterator of pairs into 2 alternating tuples."""

    def __init__(self, iter):
        self.iter = iter
        self.item = None
        self.count = 0

    def __iter__(self):
        return self

    def __next__(self):
        val = None
        if self.count % 2 == 0:
            self.item = self.iter.next()
            val = self.item[0]
        else:
            val = self.item[1]
        ret = (f"[{self.count}]", val)
        self.count += 1
        return ret

    next = __next__


class ValueIterator:
    """This iterator returns a ('[i]',value) tuple from an iterator."""

    def __init__(self, iter):
        self.iter = iter
        self.count = 0

    def __iter__(self):
        return self

    def __next__(self):
        value = self.iter.next()
        ret = (f"[{self.count}]", value)
        self.count = self.count + 1
        return ret

    next = __next__


###############################################################################
# Public Type Printers
###############################################################################
class IPv4Address:
    """Pretty printer for 'bteso_IPv4Address'

    Prints the address in dotted decimal notation with the port separated by a
    colon.

         192.10.1.5:8194
    """

    def __init__(self, val):
        self.val = val
        self.port = val["d_portNumber"]
        ip = int(val["d_address"])
        self.a = ip & 0xFF
        self.b = (ip >> 8) & 0xFF
        self.c = (ip >> 16) & 0xFF
        self.d = (ip >> 24) & 0xFF

    def to_string(self):
        return f"{self.a}.{self.b}.{self.c}.{self.d}:{self.port}"


class Nullable:
    """Pretty printer for 'bdlb::NullableValue<T>' and 'bsl::optional<T>'

    This pretty printer handles both the allocator aware and not allocator
    aware types internally. It supports both BDE-specific structure
    (d_value/d_hasValue/d_buffer) and std::optional-like structure
    (_M_payload/_M_engaged) for cases where bsl::optional inherits from
    std::optional.

    The output contains the type name and [null] if the value is null and a
    child with the value otherwise.

        intNullable = bdlb::NullableValue<int> [null]

        stringOptional = bsl::optional<bsl::string> {
            value = bsl::string [size:15,capacity:23] "optional string"
        }

    The allocator child will be added if the nullable is allocator-aware
    and allocator printing is on.
    """

    def __init__(self, val):
        self.val = val
        self.type = val.type.template_argument(0)
        self.members = {}

        if hasMember(val, "d_value"):
            if val["d_value"]["d_hasValue"]:
                buf = val["d_value"]["d_buffer"]["d_buffer"]
                self.members["value"] = buf.cast(self.type.pointer()).dereference()

            if hasMember(val["d_value"], "d_allocator"):
                self.alloc = _allocatorResource(val["d_value"]["d_allocator"])
                self.members.update(_allocatorDict(self.alloc))
        else:
            if val["_M_payload"]["_M_engaged"]:
                self.members["value"] = val["_M_payload"]["_M_payload"]["_M_value"]

    def to_string(self):
        if "value" in self.members:
            return simplifyTypeName(self.val.type)
        else:
            return f"{simplifyTypeName(self.val.type)} [null]"

    def children(self):
        return iter(self.members.items())


class Time:
    """Pretty printer for 'bdlt::Time'

    The value is shown in 'hh:mm:ss.xxx' format.
    """

    def __init__(self, val):
        self.val = val

    @classmethod
    def toHMmS(cls, value):
        milliseconds = value % 1000
        value //= 1000
        seconds = value % 60
        value //= 60
        minutes = value % 60
        value //= 60
        hours = value

        return f"{hours:02d}:{minutes:02d}:{seconds:02d}.{milliseconds:03d}"

    @classmethod
    def toHMuS(cls, value):
        microseconds = value % 1000000
        value //= 1000000
        seconds = value % 60
        value //= 60
        minutes = value % 60
        value //= 60
        hours = value

        return f"{hours:02d}:{minutes:02d}:{seconds:02d}.{microseconds:06d}"

    def to_string(self):
        us = int(self.val["d_value"])
        mask = 0x4000000000
        if us < mask:
            return f"invalid time value {us}"
        return Time.toHMuS(us & ~mask)


class Tz:
    """Utility to format a time zone offset."""

    @classmethod
    def toHM(cls, offset):
        offset = int(offset)
        if offset < 0:
            offset = -offset
            sign = "-"
        else:
            sign = "+"
        return f"{sign}{offset // 60:02d}:{offset % 60:02d}"


class TimeTz:
    """Pretty printer for 'bdlt::TimeTz'

    The value is shown in 'hh:mm:ss.xxx+hh:mm' format.
    """

    def __init__(self, val):
        self.val = val

    def to_string(self):
        time = Time(self.val["d_localTime"]).to_string()
        return f"{time}{Tz.toHM(self.val['d_offset'])}"


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
    YEAR_1752_NUM_MISSING_DAYS = 11
    DAYS_IN_NON_LEAP_YEAR = 365
    DAYS_IN_LEAP_YEAR = DAYS_IN_NON_LEAP_YEAR + 1
    DAYS_IN_4_YEARS = 3 * DAYS_IN_NON_LEAP_YEAR + DAYS_IN_LEAP_YEAR
    DAYS_IN_100_YEARS = 25 * DAYS_IN_4_YEARS - 1
    DAYS_IN_400_YEARS = 4 * DAYS_IN_100_YEARS + 1

    y1752DaysThroughMonth = [
        0,
        31,
        60,
        91,
        121,
        152,
        182,
        213,
        244,
        263,
        294,
        324,
        355,
    ]
    normDaysThroughMonth = [
        0,
        31,
        59,
        90,
        120,
        151,
        181,
        212,
        243,
        273,
        304,
        334,
        365,
    ]
    leapDaysThroughMonth = [
        0,
        31,
        60,
        91,
        121,
        152,
        182,
        213,
        244,
        274,
        305,
        335,
        366,
    ]

    def __init__(self, val):
        self.val = val

    @classmethod
    def serialToYearDate(cls, serialDay):
        """Extract the year and day of the year from the value in 'serialDay'."""
        serialDay = int(serialDay)
        if serialDay > Date.JAN_01_1753:
            y = Date.YEAR_1601  # base year
            n = serialDay - Date.JAN_01_1601  # num actual days since 1601/1/1

            m = n + Date.YEAR_1752_NUM_MISSING_DAYS - 1
            # Compensate for the 11 missing days in September of 1752, and
            # the additional leap day in 1700.

            z400 = m // Date.DAYS_IN_400_YEARS  # num 400-year blocks
            y += z400 * 400
            m -= z400 * Date.DAYS_IN_400_YEARS  # num days since y/1/1 (400)

            z100 = m // Date.DAYS_IN_100_YEARS  # num 100-year blocks
            y += z100 * 100
            m -= z100 * Date.DAYS_IN_100_YEARS  # num days since y/1/1 (100)

            z4 = m // Date.DAYS_IN_4_YEARS  # num 4-year blocks
            y += z4 * 4
            m -= z4 * Date.DAYS_IN_4_YEARS  # num days since y/1/1 (4)

            z = m // Date.DAYS_IN_NON_LEAP_YEAR  # num whole years
            y += z
            m -= z * Date.DAYS_IN_NON_LEAP_YEAR  # num days since y/1/1 (1)

            if 0 == m and (4 == z or 4 == z100):  # last day in a leap yeear or
                # a leap year every 400 years
                year = y - 1
                dayOfYear = Date.DAYS_IN_LEAP_YEAR
            else:
                year = y
                dayOfYear = m + 1
            return (year, dayOfYear)
        else:
            # Date pre-1753
            y = 1  # base year
            n = serialDay - 1  # num actual days since 1/1/1

            z4 = n // Date.DAYS_IN_4_YEARS  # num 4-year blocks
            y += z4 * 4
            n -= z4 * Date.DAYS_IN_4_YEARS  # num days since y/1/1 (4)

            z = n // Date.DAYS_IN_NON_LEAP_YEAR  # num whole years
            y += z
            n -= z * Date.DAYS_IN_NON_LEAP_YEAR  # num days since y/1/1 (1)

            if 4 == z and 0 == n:  # last day in a leap year
                year = y - 1
                dayOfYear = Date.DAYS_IN_LEAP_YEAR
            else:
                year = y
                dayOfYear = n + 1
            return (year, dayOfYear)

    @classmethod
    def isLeapYear(cls, year):
        return 0 == year % 4 and (0 != year % 100 or 0 == year % 400 or year <= 1752)

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

        if (
            year == Date.YEAR_1752
            and m == Date.SEPTEMBER
            and d >= Date.YEAR_1752_FIRST_MISSING_DAY
        ):
            d += Date.YEAR_1752_NUM_MISSING_DAYS

        return (m, d)

    @classmethod
    def toYMD(cls, serialDay):
        (year, dayOfYear) = Date.serialToYearDate(serialDay)
        (month, day) = Date.dayOfYearToDayMonth(year, dayOfYear)

        return f"{year:04d}-{month:02d}-{day:02d}"

    def to_string(self):
        return Date.toYMD(self.val["d_serialDate"])


class DateTz:
    """Pretty printer for 'bdlt::DateTz'

    The value is shown in 'YYYYY-MM-DDT00+hh:mm' format.
    """

    def __init__(self, val):
        self.val = val

    def to_string(self):
        date = Date(self.val["d_localDate"]).to_string()
        return f"{date}T00{Tz.toHM(self.val['d_offset'])}"


class Datetime:
    """Pretty printer for 'bdlt::Datetime'

    The value is shown in 'YYYYY-MM-DDTHH:MM:SS.SSSSSS' format.
    """

    REP_MASK = 0x08000000000000000
    DATE_MASK = 0x0FFFFFFE000000000
    TIME_MASK = 0x00000001FFFFFFFFF
    MASK_32 = 0x000000000FFFFFFFF
    SHIFT_32 = 32
    TIME_BITS = 37

    def __init__(self, val):
        self.val = val

    def to_string(self):
        value = int(self.val["d_value"])
        if value < 0:
            value += 2**64
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

        return f"{'[invalid]' if invalid else ''}{date}T{time}"


class DatetimeTz:
    """Pretty printer for 'bdlt::DatetimeTz'

    The value is shown in 'YYYYY-MM-DDThh:mm:ss.ssssss+hh:mm' format.
    """

    def __init__(self, val):
        self.val = val

    def to_string(self):
        datetime = Datetime(self.val["d_localDatetime"]).to_string()
        return f"{datetime}{Tz.toHM(self.val['d_offset'])}"


class BslString:
    """Printer for 'bsl::string'.

    The pretty printer for 'bsl::string' ('bsl::basic_string<char>') uses the
    pretty printer for 'StringImp'.  See the documentation below to interpret
    the printout.

        string = bsl::string [size:11,capacity:19] "Hello there"

    Note that while common pretty printers for 'std::string' will only dump the
    contents ("Hello there"), printing out the allocator ('bslma::Allocator*')
    helps detect bugs when a member of a type might not be using the same
    allocator as the container.  The size and, to lesser extent, capacity and
    use of small string optimization can help detect other issues and do not
    add too much verbosity to the output.  Allocator is displayed as a child
    when allocator printing is enabled.

        string = bsl::string [size:11,capacity:19] "Hello there" {
            alloc = 0x4e3ce0 <BloombergLP::g_newDeleteAllocatorSingleton>
        }

    See also: 'BslStringImp'
    """

    def __init__(self, val):
        self.val = val
        self.members = {}

        # First base is String_Imp
        simp = val.cast(getBaseType(val, 0))
        self.simp = BslStringImp(simp)

        self.alloc = _allocatorResource(val["d_allocator"])
        self.members.update(_allocatorDict(self.alloc))

    def to_string(self):
        return f"{simplifyTypeName(self.val.type)} {self.simp.to_string()}"

    def children(self):
        return iter(self.members.items())


class StringRefData:
    """Printer for bslstl::StringRef implementation data

    The format of the output is [length:6] "abcdef"
    """

    def __init__(self, val):
        self.val = val

    def to_string(self):
        if hasMember(self.val, "d_start_p"):
            buffer = self.val["d_start_p"]
            length = self.val["d_length"]
        else:
            buffer = self.val["_M_str"]
            length = self.val["_M_len"]
        return (
            f"{stringAddress(buffer)}[length:{length}]"
            f' "{stringRep(buffer, length)}"'
        )


class StringRef:
    """Printer for bslstl::StringRef

    The format of the output is bslstl::StringRef [length:2] "ab"
    """

    def __init__(self, val):
        self.val = val
        self.imp = StringRefData(val.cast(getBaseType(val, 0)))

    def to_string(self):
        return f"{simplifyTypeName(self.val.type)} {self.imp.to_string()}"


class BslVector:
    """Printer for 'bsl::vector<T,bsl::allocator<T>>'

    The pretty printer for specializations of 'bsl::vector<>' is implemented
    in terms of the 'VectorImp' pretty printer.  When allocator printing is
    disabled, elements are direct children of the vector:

        vector = bsl::vector<int> [size:3,capacity:4] {
            [0] = 1
            [1] = 2
            [2] = 3
        }

    When allocator printing is enabled, the vector will have a child 'data'
    that holds the 'bsl::vectorBase<T>' implementation, and the elements will
    be children of the 'data' child:

        vector = bsl::vector<int> [size:3,capacity:4] {
            data = [size:3,capacity:4] {
                [0] = 1
                [1] = 2
                [2] = 3
            }
            alloc = 0x4e3ce0 <BloombergLP::g_newDeleteAllocatorSingleton>
        }

    See also 'BslVectorImp'
    """

    def __init__(self, val):
        self.val = val
        self.members = {}

        vimp = val.cast(getBaseType(val, 0))
        self.vimp = BslVectorImp(vimp)
        self.members["data"] = vimp

        self.alloc = _allocatorResource(val["d_allocator"])
        self.members.update(_allocatorDict(self.alloc))

    def to_string(self):
        return f"{simplifyTypeName(self.val.type)} {self.vimp.to_string()}"

    def children(self):
        if "alloc" in self.members:
            return iter(self.members.items())
        else:
            return self.vimp.children()


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
        self.keyArg = val.type.template_argument(0)
        self.valueArg = val.type.template_argument(1)

        self.valueType = gdb.lookup_type(
            f"bsl::pair<{self.keyArg.const()}, {self.valueArg} >"
        )
        self.size = val["d_tree"]["d_numNodes"]
        self.alloc = _allocatorResource(val["d_compAndAlloc"]["d_pool"]["d_pool"])
        self.sentinel = val["d_tree"]["d_sentinel"]

    def to_string(self):
        # Locally handle the printing the allocator or not
        return (
            f"{simplifyTypeName(self.val.type)} [size:{self.size}{_optionalAllocator(self.alloc)}]"
        )

    def display_hint(self):
        return "map"

    def children(self):
        return KeyValueIterator(
            PairTupleIterator(BslRbTreeIterator(self.valueType, self.sentinel))
        )


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

        self.size = val["d_tree"]["d_numNodes"]
        self.alloc = _allocatorResource(val["d_compAndAlloc"]["d_pool"]["d_pool"])
        self.sentinel = val["d_tree"]["d_sentinel"]

    def to_string(self):
        # Locally handle the printing the allocator or not
        return (
            f"{simplifyTypeName(self.val.type)} [size:{self.size}{_optionalAllocator(self.alloc)}]"
        )

    def display_hint(self):
        return "array"

    def children(self):
        return ValueIterator(BslRbTreeIterator(self.valueType, self.sentinel))


class BslUnorderedMap:
    """Printer for a bsl::unordered_map<K,V>"""

    def __init__(self, val):
        self.val = val
        self.impl = val["d_impl"]
        self.size = int(self.impl["d_size"])
        self.capacity = int(self.impl["d_capacity"])
        self.alloc = _allocatorResource(
            self.impl["d_parameters"]["d_nodeFactory"]["d_pool"]
        )
        self.keyArg = val.type.template_argument(0)
        self.valueArg = val.type.template_argument(1)

        self.valueType = gdb.lookup_type(
            f"bsl::pair<{self.keyArg.const()}, {self.valueArg} >"
        )

        anchor = self.impl["d_anchor"]
        self.buckets = int(anchor["d_bucketArraySize"])
        self.listRoot = anchor["d_listRootAddress_p"]

    def to_string(self):
        return (
            f"{simplifyTypeName(self.val.type)} [size:{self.size},capacity:{self.capacity},"
            f"buckets:{self.buckets}{_optionalAllocator(self.alloc)}]"
        )

    def display_hint(self):
        return "map"

    def children(self):
        return KeyValueIterator(
            PairTupleIterator(HashTableIterator(self.valueType, self.listRoot))
        )


class BslUnorderedSet:
    """Printer for a bsl::unordered_set<V>"""

    def __init__(self, val):
        self.val = val
        self.impl = val["d_impl"]
        self.size = int(self.impl["d_size"])
        self.capacity = int(self.impl["d_capacity"])
        self.alloc = _allocatorResource(
            self.impl["d_parameters"]["d_nodeFactory"]["d_pool"]
        )
        self.valueType = val.type.template_argument(0)

        anchor = self.impl["d_anchor"]
        self.buckets = int(anchor["d_bucketArraySize"])
        self.listRoot = anchor["d_listRootAddress_p"]

    def to_string(self):
        return (
            f"{simplifyTypeName(self.val.type)} [size:{self.size},capacity:{self.capacity},"
            f"buckets:{self.buckets}{_optionalAllocator(self.alloc)}]"
        )

    def display_hint(self):
        return "array"

    def children(self):
        return ValueIterator(HashTableIterator(self.valueType, self.listRoot))


class BslPair:
    """Pretty printer for 'bsl::pair'"""

    def __init__(self, val):
        self.val = val
        self.members = {"first": val["first"], "second": val["second"]}

    def to_string(self):
        return simplifyTypeName(self.val.type)

    def children(self):
        return iter(self.members.items())


class BslAtomic:
    """Pretty printer for bsls::Atomic* types

    This will only print the internal value, whether a 32, 64 bit integer or
    a pointer.  In the case of a pointer, if you need to dereference it, the
    member storing the value is 'ptr.d_value.d_value'.

    Example outputs:

        bsls::AtomicInt = 64
        bsls::AtomicPointer<int> = 0x0
    """

    def __init__(self, val):
        self.val = val
        self.value = val["d_value"]["d_value"]

    def to_int(self):
        """Return the value of this atomic value as 'int'"""
        return int(self.value)

    def to_string(self):
        return f"{simplifyTypeName(self.val.type)} = {self.value}"


class BslSharedPtr:
    """Pretty printer for 'bsl::shared_ptr<TYPE>' and 'bsl::weak_ptr<TYPE>'

    This pretty printer will display the shared/weak pointer reference count
    and the value of the pointed object.  The format of the output will be
    bsl::shared_ptr<type> [ref:n,weak:n] = {*d_ptr_p = ...} (and the same for
    bsl::weak_ptr).  If the pointer is null, the output shows
    bsl::shared_ptr<type> [ref:0,weak:0] = null with d_ptr_p = null in the
    children view.

    The printer handles various null and invalid pointer states gracefully,
    including cases where the representation pointer is null or the data
    pointer is inaccessible.
    """

    def __init__(self, val):
        self.val = val
        self.type = val.type.template_argument(0)
        ptr = val["d_ptr_p"]
        rep = val["d_rep_p"]

        # Handle null representation pointer
        if rep == 0:
            self.shared = 0
            self.weak = 0
        else:
            # adjusted shared count holds 2*count + X
            # where X == 1 if at least 1 weak ptr was created
            self.shared = BslAtomic(rep["d_adjustedSharedCount"]).to_int() // 2
            # adjusted weak count holds 2*count + X
            # where X == 1 if there are outstanding shared ptrs
            self.weak = BslAtomic(rep["d_adjustedWeakCount"]).to_int() // 2

        # Handle null data pointer
        if ptr == 0 or ptr is None:
            self.members = {"d_ptr_p": "null"}
            self.is_null = True
        else:
            try:
                self.members = {"*d_ptr_p": ptr.dereference()}
                self.is_null = False
            except gdb.error:
                # Handle case where pointer is invalid/inaccessible
                self.members = {"d_ptr_p": f"{ptr} (invalid)"}
                self.is_null = True

    def to_string(self):
        return (
            f"{simplifyTypeName(self.val.type)} [ref:{self.shared},weak:{self.weak}]"
            f'{" [null]" if self.is_null else ""}'
        )

    def children(self):
        return iter(self.members.items())


class BslmaManagedPtr:
    """Pretty printer for 'bslma::ManagedPtr<TYPE>'

    This pretty printer will print either "<NULL>" or the contents of the
    object pointed by the managed pointer.

    TODO: Detect whether the deleter is an allocator and print it if the
          configuration is set to print allocator pointers.
    """

    def __init__(self, val):
        self.val = val
        self.type = val.type.template_argument(0)
        self.ptr = val["d_members"]["d_obj_p"]
        if self.ptr == 0:
            self.null = True
            self.members = {"d_obj_p": "null"}
        else:
            self.null = False
            self.ptr = self.ptr.cast(self.type.pointer())
            try:
                self.members = {"*d_obj_p": self.ptr.dereference()}
            except gdb.error:
                # Handle case where pointer is invalid/inaccessible
                self.members = {"d_obj_p": f"{self.ptr} (invalid)"}

    def to_string(self):
        return f'{simplifyTypeName(self.val.type)}{" [null]" if self.null else ""}'

    def children(self):
        return iter(self.members.items())


class BdldfpDecimal64:
    """Pretty printer for 'bdldfp::Decimal64' type

    This pretty printer will print the scientific notation of the decimal.
    """

    SIGN_MASK = 0x8000000000000000
    SPECIAL_ENCODING_MASK = 0x6000000000000000
    INFINITY_MASK = 0x7800000000000000
    NAN_MASK = 0x7C00000000000000
    SMALL_COEFF_MASK = 0x0007FFFFFFFFFFFF
    LARGE_COEFF_MASK = 0x001FFFFFFFFFFFFF
    LARGE_COEFF_HIGH_BIT = 0x0020000000000000
    EXPONENT_MASK = 0x3FF
    EXPONENT_SHIFT_LARGE = 51
    EXPONENT_SHIFT_SMALL = 53
    DECIMAL_EXPONENT_BIAS = 398

    def __init__(self, val):
        self.val = val
        self.type = val.type
        self.members = {"d_value": val["d_value"]}
        self.raw = val["d_value"]["d_raw"]

        if (self.raw & BdldfpDecimal64.SIGN_MASK) == 0:
            self.sign = ""
        else:
            self.sign = "-"

        self.is_nan = (self.raw & BdldfpDecimal64.NAN_MASK) == BdldfpDecimal64.NAN_MASK
        self.is_inf = (
            self.raw & BdldfpDecimal64.INFINITY_MASK
        ) == BdldfpDecimal64.INFINITY_MASK
        if (
            self.raw & BdldfpDecimal64.SPECIAL_ENCODING_MASK
        ) == BdldfpDecimal64.SPECIAL_ENCODING_MASK:
            if self.is_inf:
                self.significand = (
                    self.raw & BdldfpDecimal64.SMALL_COEFF_MASK
                ) | BdldfpDecimal64.LARGE_COEFF_HIGH_BIT
                tmp = self.raw >> BdldfpDecimal64.EXPONENT_SHIFT_LARGE
                self.exponent = tmp & BdldfpDecimal64.EXPONENT_MASK
            else:
                self.significand = (
                    self.raw & BdldfpDecimal64.SMALL_COEFF_MASK
                ) | BdldfpDecimal64.LARGE_COEFF_HIGH_BIT
                tmp = self.raw >> BdldfpDecimal64.EXPONENT_SHIFT_LARGE
                self.exponent = (
                    tmp & BdldfpDecimal64.EXPONENT_MASK
                ) - BdldfpDecimal64.DECIMAL_EXPONENT_BIAS
        else:
            tmp = self.raw >> BdldfpDecimal64.EXPONENT_SHIFT_SMALL
            self.exponent = (
                tmp & BdldfpDecimal64.EXPONENT_MASK
            ) - BdldfpDecimal64.DECIMAL_EXPONENT_BIAS
            self.significand = self.raw & BdldfpDecimal64.LARGE_COEFF_MASK

    def to_string(self):
        if self.is_nan:
            return "sNaN" if self.sign == "-" else "NaN"
        elif self.is_inf:
            return self.sign + "Inf"
        elif self.significand == 0:
            return self.sign + "0"

        approximate_field_width = 16

        significand = str(self.significand)
        exponent = int(self.exponent)

        # Try to print the number naturally
        if exponent >= 0:
            if len(significand) + exponent <= approximate_field_width:
                return significand + ("0" * exponent)
        elif -exponent < len(significand):
            return significand[:exponent] + "." + significand[exponent:]
        elif -exponent == len(significand):
            return "0." + significand
        elif -exponent < approximate_field_width:
            return "0." + ("0" * (-exponent - len(significand))) + significand

        # If the exponent is too big, print in scientific notation.
        exponent = int(self.exponent + len(significand) - 1)
        digit = significand[0]
        fraction = significand[1:].rstrip("0")
        if len(fraction) == 0:
            fraction = "0"

        return "{}{}.{}e{:+}".format(self.sign, digit, fraction, exponent)

    def children(self):
        try:
            printMembers = gdb.parameter("print ria-members")
            if printMembers:
                return iter(self.members.items())
        except:
            pass
        return []


class Variant:
    """Pretty printer for 'bsl::variant<TYPES...>'

    This pretty printer handles the variant by checking the active index
    and displaying either the contained value at that index or indicating
    if the variant is valueless by exception.

    The output shows the active alternative type and its value.
    """

    def __init__(self, val):
        self.val = val
        self.members = {}

        # Get the current active index
        d_type = val["d_type"]

        # Check if variant is valueless by exception (variant_npos is (size_t)-1)
        variant_npos = (
            (1 << 64) - 1 if gdb.lookup_type("size_t").sizeof == 8 else (1 << 32) - 1
        )
        if int(d_type) == variant_npos:
            self.members["valueless_by_exception"] = True
        else:
            # Navigate the union structure directly to find the active alternative
            try:
                # Navigate through the union to find the active alternative
                union_val = val["d_union"]
                current_index = int(d_type)

                # Navigate down the recursive union structure
                # Each level decrements the index and goes to d_tail until index is 0
                while current_index > 0:
                    try:
                        union_val = union_val["d_tail"]
                        current_index -= 1
                    except (gdb.error, AttributeError):
                        # Can't access d_tail - corrupted state or invalid index
                        self.members["error"] = (
                            f"Cannot navigate to index {int(d_type)} -"
                            " corrupted state or invalid index"
                        )
                        return

                # At index 0, we should have the active alternative in d_head
                try:
                    # Check if d_head exists
                    d_head = union_val["d_head"]

                    # Get the type of the active alternative from the union's
                    # first template argument
                    union_type = union_val.type.strip_typedefs()
                    active_type = union_type.template_argument(
                        0
                    )  # First template argument of Variant_Union

                    # Get the stored value from d_head's buffer
                    try:
                        stored_value = (
                            d_head["d_buffer"]["d_buffer"]
                            .cast(active_type.pointer())
                            .dereference()
                        )
                    except (gdb.error, AttributeError) as e:
                        self.members["error"] = (
                            f"Cannot access buffer at index {int(d_type)}: {str(e)}"
                        )
                        return

                    self.members["index"] = d_type
                    self.members["value"] = stored_value
                    self.active_type = simplifyTypeName(active_type)

                    if hasMember(val, "d_allocator"):
                        self.alloc = _allocatorResource(val["d_allocator"])
                        self.members.update(_allocatorDict(self.alloc))

                except (gdb.error, AttributeError) as e:
                    # Can't access d_head - corrupted state
                    self.members["error"] = (
                        f"Cannot access d_head at index {int(d_type)} -"
                        f" corrupted state: {str(e)}"
                    )

            except (gdb.error, RuntimeError, AttributeError) as e:
                self.members["error"] = f"Failed to extract value: {str(e)}"

    def to_string(self):
        typeName = simplifyTypeName(self.val.type)
        # Check if valueless by exception
        if "valueless_by_exception" in self.members:
            return f"{typeName} [valueless_by_exception]"
        elif "value" in self.members:
            return f"{typeName} [{self.active_type}]"
        elif "error" in self.members:
            return f"{typeName} [error: {self.members['error']}]"

        return typeName

    def children(self):
        return iter(self.members.items())


class BdlbVariant:
    """Pretty printer for 'bdlb::Variant<TYPES...>' and 'bdlb::VariantN<TYPES...>'

    This pretty printer handles the bdlb variant by checking the active type index
    and displaying either the contained value at that index or indicating
    if the variant is unset.

    The output shows the active alternative type and its (1-based) index and
    value as children.

    For example:
        variant2 = bdlb::Variant2<int, bsl::string> [int] {
            index = 1
            value = 42
        }
        variant3 = bdlb::Variant3<int, double, bsl::string> [bsl::string] {
            index = 3
            value = bsl::string [size:11,capacity:19] "Hello there"
        }
        bdlb::Variant<int, bsl::string> [unset]
    """

    def __init__(self, val):
        self.val = val
        self.members = {}

        # Get the current active type index
        d_type = int(val["d_type"])

        # Check if variant is unset (type index is 0)
        if d_type == 0:
            self.members["unset"] = True
        else:
            try:
                # Get the union containing the values
                d_value = val["d_value"]

                # bdlb::Variant types are 1-indexed, so we need to access
                # d_v{d_type}
                value_field_name = f"d_v{d_type}"

                # Access the ObjectBuffer for the active type
                object_buffer = d_value[value_field_name]

                # Get the type from the ObjectBuffer's template parameter
                object_buffer_type = object_buffer.type.strip_typedefs()
                stored_type = object_buffer_type.template_argument(0)

                # Get the actual object from the ObjectBuffer
                # # The ObjectBuffer contains the object in its internal buffer
                # We need to cast the buffer address to the correct type
                # pointer and dereference it
                buffer_address = object_buffer.address.cast(stored_type.pointer())
                stored_object = buffer_address.dereference()

                self.members["index"] = d_type
                self.members["value"] = stored_object
                self.stored_type = simplifyTypeName(stored_type)

            except (gdb.error, RuntimeError, AttributeError) as e:
                self.members["error"] = f"Failed to extract value: {str(e)}"

    def to_string(self):
        typeName = simplifyTypeName(self.val.type)
        # Check if unset
        if "unset" in self.members:
            return f"{typeName} [unset]"
        elif "value" in self.members:
            return f"{typeName} [{self.stored_type}]"
        elif "error" in self.members:
            return f"{typeName} [error: {self.members['error']}]"

        return typeName

    def children(self):
        return iter(self.members.items())


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
            print("""
    Usage: bde-help [element]

        Prints the documentation for 'element'.

        bde-help            -- show documentation for the whole module
        bde-help BslString  -- show documentation for the BslString printer
""")


class BslShowAllocatorParameter(gdb.Parameter):
    """Control whether the bslma::Allocator is printed in each object.

    The allocator in use inside an object of container is an important piece of
    information, and printing the allocator can help debug issues where the
    allocator is not properly "injected" into the members of a type.  On the
    other hand, when debugging the logic of the application, printing the
    allocator for each member, which is by definition the same for all, can add
    noise and make it harder to read the data.
    """

    set_doc = "Controls printing the bslma::Allocator in use"
    show_doc = "Display the bslma::Allocator in use"
    value = True

    def __init__(self):
        super(BslShowAllocatorParameter, self).__init__(
            "print bslma-allocator", gdb.COMMAND_DATA, gdb.PARAM_BOOLEAN
        )

    def get_set_string(self):
        if self.value:
            return "Print bslma::Allocator"
        else:
            return "Do not print bslma::Allocator"

    def get_show_string(self, svalue):
        return f"Printing of bslma-allocator is {'on' if svalue else 'off'}."


class BslStringAddressParameter(gdb.Parameter):
    """Control whether string buffer addresses are printed."""

    set_doc = "Controls printing string buffer address"
    show_doc = "Print string buffer address"
    value = False

    def __init__(self):
        super(BslStringAddressParameter, self).__init__(
            "print string-address", gdb.COMMAND_DATA, gdb.PARAM_BOOLEAN
        )

    def get_set_string(self):
        if self.value:
            return "Printing string buffer addresses"
        else:
            return "Not printing string buffer addresses"

    def get_show_string(self, svalue):
        return f"Printing string buffer addresses is {'on' if svalue else 'off'}."


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
        docs = {}
        global pp
        pp = gdb.printing.RegexpCollectionPrettyPrinter("BDE")
    except:
        pass


def makeReferenceUnwrappingPrinter(cls):

    def unwrapReference(val):
        if val.type.code == gdb.TYPE_CODE_REF:
            return val.referenced_value()
        return val

    class ReferenceUnwrappingPrinter(cls):
        def __init__(self, val):
            super().__init__(unwrapReference(val))

    return ReferenceUnwrappingPrinter


def add_printer(name, re, klass):
    global docs
    docs[name] = klass.__doc__
    # docs[klass.__name__] = klass.__doc__
    global pp
    pp.add_printer(name, re, makeReferenceUnwrappingPrinter(klass))


def build_pretty_printer():
    add_printer("bteso_IPv4Address", "^BloombergLP::bteso_IPv4Address$", IPv4Address)
    add_printer("bdlb::NullableValue", "BloombergLP::bdlb::NullableValue<.*>", Nullable)
    add_printer("bsl::optional", "^bsl::optional<.*>$", Nullable)
    add_printer("bsl::variant", "^bsl::variant<.*>$", Variant)
    add_printer("bdlb::Variant", "^BloombergLP::bdlb::Variant<.*>$", BdlbVariant)
    for i in range(2, 20):
        add_printer(
            f"bdlb::Variant{i}",
            f"^BloombergLP::bdlb::Variant{i}<.*>$",
            BdlbVariant,
        )
    add_printer("bdlb::VariantImp", "^BloombergLP::bdlb::VariantImp<.*>$", BdlbVariant)
    add_printer("bdlt::Date", "^BloombergLP::bdlt::Date$", Date)
    add_printer("bdlt::DateTz", "^BloombergLP::bdlt::DateTz$", DateTz)
    add_printer("bdlt::Datetime", "^BloombergLP::bdlt::Datetime$", Datetime)
    add_printer("bdlt::DatetimeTz", "^BloombergLP::bdlt::DatetimeTz$", DatetimeTz)
    add_printer("bdlt::Time", "^BloombergLP::bdlt::Time$", Time)
    add_printer("bdlt::TimeTz", "^BloombergLP::bdlt::TimeTz$", TimeTz)

    add_printer("string", "^bsl::basic_string<char,.*>$", BslString)
    add_printer("(internal)StringImp", "^bsl::String_Imp<char,.*>$", BslStringImp)
    add_printer(
        "bslstl::StringRef",
        "^BloombergLP::bslstl::StringRefImp<char>$",
        StringRef,
    )
    add_printer(
        "(internal)StringRefData",
        "^BloombergLP::bslstl::StringRefData<char>$",
        StringRefData,
    )

    add_printer("(internal)VectorImp", "^bsl::vectorBase<.*>", BslVectorImp)
    add_printer("vector", "^bsl::vector<.*>$", BslVector)

    add_printer("map", "^bsl::map<.*>$", BslMap)
    add_printer("set", "^bsl::set<.*>$", BslSet)

    add_printer("unordered_map", "^bsl::unordered_map<.*>$", BslUnorderedMap)
    add_printer("unordered_set", "^bsl::unordered_set<.*>$", BslUnorderedSet)

    add_printer("pair", "^bsl::pair<.*>$", BslPair)

    add_printer("atomic", "^BloombergLP::bsls::Atomic.*$", BslAtomic)

    add_printer("shared_ptr", "^bsl::shared_ptr<.*>$", BslSharedPtr)
    add_printer("weak_ptr", "^bsl::weak_ptr<.*>$", BslSharedPtr)
    add_printer(
        "bslma::ManagedPtr",
        "^BloombergLP::bslma::ManagedPtr<.*>$",
        BslmaManagedPtr,
    )
    add_printer(
        "bdldfp::Decimal64",
        "^BloombergLP::bdldfp::Decimal_Type64$",
        BdldfpDecimal64,
    )

    # add_printer('catchall', '.*', CatchAll)
    global pp
    return pp


def reload():
    ## Create the commands
    init_globals()
    BslShowAllocatorParameter()
    BdeHelpCommand()
    BslStringAddressParameter()

    ## Remove the pretty printer if it exists
    for printer in gdb.pretty_printers:
        if not hasattr(printer, "name"):
            continue
        if printer.name == "BDE":
            gdb.pretty_printers.remove(printer)
            break

    ## Create the new pretty printer
    gdb.printing.register_pretty_printer(gdb.current_objfile(), build_pretty_printer())


reload()

# (gdb) python execfile(\
#           "/bb/bde/bbshr/bde-tools/contrib/gdb-printers/bde_printer.py")
