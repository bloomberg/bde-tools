#!/usr/bin/python

import cgi
import glob
import os
import pprint
import sqlite3
import re
import sys

#>>> from datetime import datetime
#>>> datetime.strptime("20150219", "%Y%m%d")
#datetime.datetime(2015, 2, 19, 0, 0)

# Enable CGI debugging output
import cgitb
cgitb.enable()

# TBD: extract all this common stuff out of results and summary.
print "Content-Type: text/html"
print

fs = cgi.FieldStorage()

search_dir = "/web_data/db/"
files = filter(os.path.isfile, glob.glob(search_dir + "*"))
files.sort() #key=lambda x: os.path.getmtime(x))

date   = None
branch = None

if "date" in fs.keys() and "branch" in fs.keys():
    date   = fs["date"].value
    branch = fs["branch"].value
    db = search_dir+"%s-%s.db"%(branch, date)
elif "db" in fs.keys():
    db = fs["db"].value;
else:
    db = files[-1]

if date is None:
    result=re.search("-(\d+)\.db", db)
    if result is None:
        print "Unable to extract date from db %s"%db
        sys.exit(1)

    date = result.group(1)

if branch is None:
    result=re.search("(\w+)-(\d+)\.db", db)
    if result is None:
        print "Unable to extract branch from db %s"%db
        sys.exit(1)

    branch = result.group(1)

if not (re.match("^/web_data/db/[^/]+\.db$", db) or os.getuid()==(os.stat(db).st_uid)):
    print "db value %s is invalid"%db
    sys.exit(1)

if not (os.path.isfile(db) and os.access(db, os.R_OK)):
    print "Either file is missing or is not readable"
    sys.exit(1)

connection = sqlite3.connect(db)
cursor     = connection.cursor()

class Vividict(dict):
    """This class creates a dictionary with perl-like nested hash
       auto-vivification, meaning that attempts to access a non-existent
       subhash will create the missing hash.
    """

    def __missing__(self, key):
        value = self[key] = type(self)()
        return value

short_category_names = {
        "BUILD_WARNING":     "build_warn",
        "BUILD_ERROR":       "build_err",
        "TEST_WARNING":      "test_warn",
        "TEST_ERROR":        "test_err",
        "TEST_RUN_FAILURE":  "test_fail"
}

styles = {
        "build_warn":       ["background-color:black;",
                             "color:yellow;"
                            ],
        "build_err" :       ["background-color:white;",
                             "color:blue;"
                            ],
        "test_warn":        ["background-color:brown;",
                             "color:yellow;"
                            ],
        "test_err"  :       ["background-color:brown;",
                             "color:yellow;"
                            ],
        "test_fail" :       ["background-color:yellow;",
                             "color:black;"
                            ],
    }

uor_ordering = {
        "bsl"        :    0,
        "bdl"        :    1,
        "bde"        :    2,
        "bce"        :    3,
        "bae"        :    4,
        "bte"        :    5,
        "bbe"        :    6,
        "bsi"        :    7,
        "e_ipc"      :    8,
        "a_cdrdb"    :    9,
        "bap"        :    10,
        "a_comdb2"   :    11,
        "a_bdema"    :    12,
        "a_bteso"    :    13,
        "a_xercesc"  :    14,
        "bdx"        :    15,
        "zde"        :    16,
    }

def uor_key(uor):
    """Return the sorting key for the specified 'uor', in order to allow uors
       to be sorted in a reasonable order.
    """

    if not uor in uor_ordering:
        return 99

    return uor_ordering[uor]

print "<HTML>"
print "<HEAD>"
print "<TITLE>Results from %s</TITLE>"%(db)

print "<STYLE>"
print """
.default {
    background-color: black;
    color:            white;
}

table {
    border-collapse: collapse;
}

tr {
    border: none
}

td, th {
    border-left:  solid 1px #777;
    border-right: solid 1px #777;
    padding-left:  5px;
}

#.fixed thead {
#}
#.fixed thead tr {
#  display: block;
#  position: relative;
#}
#.fixed tbody {
#  display: block;
#  overflow: auto;
#  width: 100%;
#  height: 1000px;
#  overflow-y: scroll;
#    overflow-x: hidden;
#}


"""

for style in styles:
    print ".%s {" % (style)
    for formatting in styles[style]:
        print "    %s"%(formatting)
    print "}"

print "</STYLE>"

print "</HEAD>"
print "<BODY class=\"default\">"

cursor.execute("SELECT * FROM aggregated_results_at_uor_name_level")

results           = Vividict()
axis_values       = Vividict()
uplid_ufid_combos = Vividict()

uors              = {}
uplids            = {}
ufids             = {}
category_names    = {}

for result in cursor.fetchall():
    #print result
    results[result[0]][result[1]][result[2]][result[3]] = result[4]
    uors[result[0]]=1
    uplids[result[1]]=1
    ufids[result[2]]=1
    uplid_ufid_combos[result[1]][result[2]]=1
    category_names[result[3]]=1
    for index in range(0, 4):
        axis_values[index][result[index]]=1

sorted_uors = sorted(uors, key=uor_key)

print "<H1 align=\"center\">Results from %s</H1>"%db
key = "<P>"

for category in ("BUILD_ERROR","TEST_ERROR","TEST_RUN_FAILURE"):
    key += "<SPAN class=\"%s\">%s</SPAN>\n"%(short_category_names[category],
                                          category)
key += "</P>"


table_text=""

print key
print "<TABLE class=\"fixed\">"

print "<THEAD>"
print "<TR><TH></TH>"
for uor in sorted_uors:
    print "<TH>%s</TH>"%(uor)
print "</TR>"
print "</THEAD>"

print "<TBODY>"
for uplid in sorted(uplids):
    print "<TR><TH>%s</TH><TR>"%(uplid)
    for ufid in sorted(ufids):
        if not ((uplid in uplid_ufid_combos) and (ufid in uplid_ufid_combos[uplid])):
            next
        print "<TR>"
        print "<TD>%s</TD>"%(ufid)
        for uor in sorted_uors:
            inner_result=results[uor][uplid][ufid]
            print "<TD>"
            category_results={}
            #for category in ("BUILD_WARNING","BUILD_ERROR","TEST_WARNING","TEST_ERROR","TEST_RUN_FAILURE"):
            for category in ("BUILD_ERROR","TEST_ERROR","TEST_RUN_FAILURE"):
                if category in inner_result:
                    cursor.execute("""
                        SELECT component_name,
                               SUBSTR(diagnostics, 1, 500)
                        FROM build_results
                        WHERE uor_name=?
                              AND ufid=?
                              AND uplid=?
                              AND category_name=?
                        LIMIT 10
                    """,(uor, ufid, uplid, category))
                    diagnostics_text=""
                    for entry in cursor.fetchall():
                        diagnostics_text+="".join(entry)
                        diagnostics_text+="\n======\n"

                    url = "results.py?db=%s;uor=%s;uplid=%s;ufid=%s;category=%s"%(
                                db,
                                uor,
                                uplid,
                                ufid,
                                category
                            )
                    print "<A HREF=\"%s\" TARGET=\"_blank\">" % url
                    print "<SPAN TITLE=\"%s\" CLASS=%s>%d</SPAN>\n"%(
                            cgi.escape(diagnostics_text, quote=True),
                            short_category_names[category],
                            int(inner_result[category]),
                            )
                    print "</A>"
            print "</TD>"
        print "</TR>"

print "</TBODY>"


print "<TFOOT>"
print "<TR><TH></TH>"
for uor in sorted_uors:
    print "<TH>%s</TH>"%(uor)
print "</TR>"
print "</TFOOT>"

print "</TABLE>"

print key


#table2_text=table_text
#table2_text=re.sub("THEAD-STYLE", "visibility: hidden;",   table1_text)
#table2_text=re.sub("TBODY-STYLE", "visibility: visible;",  table1_text)
#print table2_text

print "</BODY>"
print "</HTML>"

if False:
    print "################## %s"%("uors")
    pprint.pprint(uors)
    print "################## %s"%("uplids")
    pprint.pprint(uplids)
    print "################## %s"%("ufids")
    pprint.pprint(ufids)
    print "################## %s"%("category_names")
    pprint.pprint(category_names)
    print "################## %s"%("axis_values")
    pprint.pprint(axis_values)

