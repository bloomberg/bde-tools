"""
   GDB pretty printer support for BDE components

   This module provides a set of pretty printers to load into gdb for debugging
   code using BDE components.

   This is a work in progress, more printers will be added as needed.

   Author: David Rodriguez Ibeas <dribeas@bloomberg.net>

   List of provided pretty printers
   --------------------------------

    Printer           Implementation type
    ---------------   -----------------------------------------------------
    BDE

   Usage
   -----
    To use the pretty printers load the script into gdb, either manually
    through:

        (gdb) python execfile('/path/to/this/script.py')

    or automatically at start up.  See the gdb documentation on how to setup
    automatic loading of pretty printers.

    You can list, enable or disable pretty printers by using the gdb commands:

        (gdb) info    pretty-printer
        (gdb) disable pretty-printer global BDE,vector
        (gdb) enable  pretty-printer global BDE

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
import gdb
import gdb.printing

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
    SEPTEMBER =  9
    YEAR_1752 = 1752
    YEAR_1601 = 1601
    JAN_01_1753 =  639908
    JAN_01_1601 =  584401
    YEAR_1752_FIRST_MISSING_DAY = 3
    YEAR_1752_NUM_MISSING_DAYS  = 11
    DAYS_IN_NON_LEAP_YEAR       = 365
    DAYS_IN_LEAP_YEAR           = 366
    DAYS_IN_4_YEARS             = 365 * 4 + 1                           #   1,461
    DAYS_IN_100_YEARS           =  25 * (365 * 4 + 1) - 1               #  36,524
    DAYS_IN_400_YEARS           =   4 * (25 * (365 * 4 + 1) - 1)   + 1  # 146,097

    y1752DaysThroughMonth = [ 0, 31,  60,  91, 121, 152, 182, 213, 244, 263, 294, 324, 355 ]
    normDaysThroughMonth  = [ 0, 31,  59,  90, 120, 151, 181, 212, 243, 273, 304, 334, 365 ]
    leapDaysThroughMonth  = [ 0, 31,  60,  91, 121, 152, 182, 213, 244, 274, 305, 335, 366 ]

    def __init__(self, val):
        self.val = val

    def serialToYearDate(self, serialDay):
        """Extract the year and day of the year from the value in 'serialDay'"""
        if serialDay > Date.JAN_01_1753:
            y = Date.YEAR_1601                  # base year
            n = serialDay - Date.JAN_01_1601         # num actual days since 1601/1/1

            m = n + Date.YEAR_1752_NUM_MISSING_DAYS - 1
                     # Compensate for the 11 missing days in September of 1752, and
                     # the additional leap day in 1700.

            z400 = m / Date.DAYS_IN_400_YEARS        # num 400-year blocks
            y += z400 * 400
            m -= z400 * Date.DAYS_IN_400_YEARS       # num days since y/1/1 (400)

            z100 = m / Date.DAYS_IN_100_YEARS        # num 100-year blocks
            y += z100 * 100
            m -= z100 * Date.DAYS_IN_100_YEARS       # num days since y/1/1 (100)

            z4 = m / Date.DAYS_IN_4_YEARS            # num 4-year blocks
            y += z4 * 4
            m -= z4 * Date.DAYS_IN_4_YEARS           # num days since y/1/1 (4)

            z = m / Date.DAYS_IN_NON_LEAP_YEAR       # num whole years
            y += z 
            m -= z * Date.DAYS_IN_NON_LEAP_YEAR      # num days since y/1/1 (1)

            if (0 == m and (4 == z or 4 == z100)):    # last day in a leap year or
                                                     # a leap year every 400 years
                year      = y - 1
                dayOfYear = Date.DAYS_IN_LEAP_YEAR
            else:
                year      = y
                dayOfYear = m + 1
            return (year, dayOfYear)
        else:
            # Date pre-1753
            y = 1;                                  # base year
            n = serialDay - 1;                      # num actual days since 1/1/1

            z4 = n / Date.DAYS_IN_4_YEARS;          # num 4-year blocks
            y += z4 * 4;
            n -= z4 * Date.DAYS_IN_4_YEARS;         # num days since y/1/1 (4)

            z = n / Date.DAYS_IN_NON_LEAP_YEAR;     # num whole years
            y += z;
            n -= z * Date.DAYS_IN_NON_LEAP_YEAR;    # num days since y/1/1 (1)

            if 4 == z and 0 == n:                   # last day in a leap year
                year      = y - 1;
                dayOfYear = Date.DAYS_IN_LEAP_YEAR;
            else:
                year      = y;
                dayOfYear = n + 1;
            return (year, dayOfYear)

    def isLeapYear(self, year):
        return 0 == year % 4 \
                and (0 != year % 100 or 0 == year % 400 or year <= 1752)

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

        if year == Date.YEAR_1752 and m == Date.SEPTEMBER and d >= Date.YEAR_1752_FIRST_MISSING_DAY:
            d += Date.YEAR_1752_NUM_MISSING_DAYS

        return (m,d)

    def to_string(self):
        serialDay = int(self.val['d_date'])

        (year, dayOfYear) = self.serialToYearDate(serialDay)
        (month, day)      = self.dayOfYearToDayMonth(year, dayOfYear)

        return "%04d-%02d-%02d" % (year, month, day)

class DateTz:
    """Pretty printer for 'bdet_DateTz'

    """
    def __init__(self,val):
        self.val = val

    def to_string(self):
        date = Date(self.val['d_localDate']).to_string()
        offset = self.val['d_offset']
        if (offset >= 0):
            return '%s +%d' % (date, offset)
        else:
            return '%s %d' % (date, offset)

###############################################################################
##
##  Create and register the pretty printers
##  ---------------------------------------
##
## Register the printers in gdb using the gdb.printing module
##
###############################################################################
def build_pretty_printer():
    pp = gdb.printing.RegexpCollectionPrettyPrinter("BDE")

    pp.add_printer('IPv4Address',
                   '^BloombergLP::bteso_IPv4Address$',
                   IPv4Address)
    pp.add_printer('NullableValue',
                   'BloombergLP::bdeut_NullableValue<.*>',
                   Nullable)
    pp.add_printer('bdet_Time',
                   'BloombergLP::bdet_Time',
                   Time);
    pp.add_printer('bdet_Date',
                   '^BloombergLP::bdet_Date$',
                   Date);
    pp.add_printer('bdet_DateTz',
                   '^BloombergLP::bdet_DateTz$',
                   DateTz);

    return pp

def reload():
    ## Remove the pretty printer if it exists
    for pp in gdb.pretty_printers:
        if (pp.name == 'BDE'):
            gdb.pretty_printers.remove(pp)
            break

    ## Create the new pretty printer
    gdb.printing.register_pretty_printer(gdb.current_objfile(),
                                         build_pretty_printer())

reload()

# (gdb) python execfile("/home/drodrig1/code/gdb-pp-stable/bde_printer.py")
