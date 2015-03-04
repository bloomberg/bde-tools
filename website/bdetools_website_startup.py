#!/usr/bin/python

import cgi
import datetime
import glob
import os
import pprint
import sqlite3
import re
import sys

# Enable CGI debugging output
import cgitb
cgitb.enable()

_dateFormat = "%Y%m%d"

_date   = datetime.date.today().strftime("%Y%m%d")
_branch = "nextrel"

_error  = ""

# TBD: extract all this common stuff out of results and summary.
print "Content-Type: text/html"
print

_fs = cgi.FieldStorage()

search_dir = "/web_data/db/"

_db     = None

"""Initialize package-global variables, or set '_error' and leave '_db' set
   to None if an error occurred.
"""

try:
    if "date" in _fs.keys() and "branch" in _fs.keys():
        _date   = _fs["date"].value
        _branch = _fs["branch"].value
        _db = search_dir+"%s-%s.db"%(_branch, _date)
    elif "date" in _fs.keys():
        _date   = _fs["date"].value
        _db = search_dir+"%s-%s.db"%(_branch, _date)
    elif "branch" in _fs.keys():
        _branch = _fs["branch"].value
        _db = search_dir+"%s-%s.db"%(_branch, _date)
    elif "db" in _fs.keys():
        _db = _fs["db"].value;
    else:
        # Limit default file search to nextrel
        files = filter(os.path.isfile, glob.glob(search_dir + "*nextrel*"))
        files.sort() #key=lambda x: os.path.getmtime(x))

        _db = files[-1]

    if _date is None:
        result=re.search("-(\d+)\.db", _db)
        if result is None:
            _error = "Unable to extract date from db %s"%_db
            _db    = None
            raise 0

        _date = result.group(1)

    if _branch is None:
        result=re.search("(\w+)-(\d+)\.db", _db)
        if result is None:
            _error = "Unable to extract branch from db %s"%_db
            _db    = None
            raise 0

        _branch = result.group(1)

    if not (re.match("^/web_data/db/[^/]+\.db$", _db) or os.getuid()==(os.stat(_db).st_uid)):
        _error = "db value %s is invalid"%_db
        _db    = None
        raise 0

    if not (os.path.isfile(_db) and os.access(_db, os.R_OK)):
        _error = "Either file %s is missing or is not readable" % _db
        _db    = None
        raise 0
except:
    pass

def db():
    """Return the name of the current database file
    """

    return _db

def error():
    """Return initialization error message, if any.
    """

    return _error

def fs():
    """Return the current CGI fieldstore.
    """

    return _fs

def date():
    """Return the current database's date.
    """

    return _date

def branch():
    """Return the current database's branch.
    """

    return _branch

def getPrevDate():
    """Return the previous date, relative to date().
    """

    dt = datetime.datetime.strptime(date(), _dateFormat)

    return (dt + datetime.timedelta(days=-1)).strftime(_dateFormat)

def getNextDate():
    """Return the next date, relative to date().
    """

    dt = datetime.datetime.strptime(date(), _dateFormat)

    return (dt + datetime.timedelta(days=1)).strftime(_dateFormat)

def getParamsString():
    """Return the parameter string that corresponds to 'fs()', omitting the
       db, date, or branch components.
    """

    paramString=""
    separator=""

    for key in fs():
        if key == 'db':
            continue

        if key == 'branch':
            continue

        if key == 'date':
            continue

        paramString+=separator+key+"="+fs()[key].value
        separator=";"

    return paramString


def getBranchDateParamString(dateParm=date(), branchParm=branch()):
    """Return the cgi-style parameter substring for the specified 'dateParm'
       date and 'branchParm' branch.
    """

    return "date=%s;branch=%s"%(dateParm, branchParm)


def printTitleRow(title, page):
    """Print the title row with the specified 'title' centered, and put in
       links to the specified 'page' for the previous and next dates.
    """

    print "<TABLE class=\"noborders\" ALIGN=\"center\" STYLE=\"width:75em;\">"

    print "<TR>"

    print "<TD ALIGN=\"LEFT\"><A HREF=\"%s?%s;%s\" TARGET=\"_blank\">Previous Date</A></TD>"%(
        page,
        getBranchDateParamString(dateParm=getPrevDate()),
        getParamsString()
        )

    print "<TD>"
    print "<A ALIGN=\"LEFT\" HREF=\"%s?%s;%s\" TARGET=\"_blank\">Nextrel</A>"%(
        page,
        getBranchDateParamString(branchParm="nextrel"),
        getParamsString()
        )
    print "</TD>"

    print  "<TD ALIGN=\"CENTER\">%s</TD>"%title

    print "<TD>"
    print "<A ALIGN=\"RIGHT\" HREF=\"%s?%s;%s\" TARGET=\"_blank\">Dev</A>"%(
        page,
        getBranchDateParamString(branchParm="dev"),
        getParamsString()
        )
    print "</TD>"

    print "<TD ALIGN=\"RIGHT\"><A HREF=\"%s?%s;%s\" TARGET=\"_blank\">Next Date</A></TD>"%(
        page,
        getBranchDateParamString(dateParm=getNextDate()),
        getParamsString()
        )

    print "</TR>"

    print "</TABLE>"



