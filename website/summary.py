#!/usr/bin/python

import cgi
import glob
import os
import pprint
import sqlite3
import re
import sys
from bdetools_website_startup import *

#>>> from datetime import datetime
#>>> datetime.strptime("20150219", "%Y%m%d")
#datetime.datetime(2015, 2, 19, 0, 0)

class Vividict(dict):
    """This class creates a dictionary with perl-like nested hash
       auto-vivification, meaning that attempts to access a non-existent
       subhash will create the missing hash.
    """

    def __missing__(self, key):
        value = self[key] = type(self)()
        return value

category_class_names = {
        "BUILD_WARNING":     "build_warn",
        "BUILD_ERROR":       "build_err",
        "TEST_WARNING":      "test_warn",
        "TEST_ERROR":        "test_err",
        "TEST_RUN_FAILURE":  "test_fail"
}

category_display_names = {
        "BUILD_WARNING":     "BUILD_WARNING",
        "BUILD_ERROR":       "BUILD_ERROR",
        "TEST_WARNING":      "TEST_WARNING",
        "TEST_ERROR":        "TEST_BUILD_ERROR",
        "TEST_RUN_FAILURE":  "TEST_RUN_ERROR"
}

styles = {
        "build_warn":       ["background-color:black;",
                             "color:orange;"
                            ],
        "build_err" :       ["background-color:white;",
                             "color:#%02x%02x%02x;"%(49, 168, 0), # Per abeels email
                            ],
        "TD-build_err" :    [
                             "border-left:  solid 1px #999;",
                            ],
        "test_warn":        ["background-color:black;",
                             "color:brown;"
                            ],
        "test_err"  :       ["background-color:white;",
                             "color:#%02x%02x%02x;"%(0,175,182), # Per abeels email
                             "font-weight:bold;",
                            ],
        "test_fail" :       ["background-color:white;",
                             "color:red;",
                             "font-style: italic;",
                            ],
        "TD-test_fail" :    [
                             "padding-right:  5px;",
                             "border-right: solid 1px #999;"
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
print "<TITLE>Results from %s - %s</TITLE>"%(date(), branch())

print "<STYLE>"
print """
.default {
    background-color: white;
    color:            black;
}

table {
    border-collapse: collapse;
}

tr {
    border: none
}

td, th {
    /*
    border-left:  solid 1px #999;
    border-right: solid 1px #999;
    */
    padding-left:  5px;
    width:         1em;
}

.noborders td, th {
    border-left: none;
    border-right: none;
    padding-left:  5px;
}

"""

for style in styles:
    print ".%s {" % (style)
    for formatting in styles[style]:
        print "    %s"%(formatting)
    print "}"

print "</STYLE>"

print "</HEAD>"
print "<BODY class=\"default\">"

printTitleRow("<H1 align=\"center\">Results from %s - %s </H1>"%(date(), branch()), "summary.py")

if db() is None:
    print "<H2>Error initializing summary for %s - %s : %s</H2>"%(date(), branch(), error())
    print "</BODY></HTML>"
    sys.exit(0)

connection = sqlite3.connect(db())
cursor     = connection.cursor()

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

#print "<H1 align=\"center\">Results from %s</H1>"%db()
key = "<P>"

for category in ("BUILD_ERROR","TEST_ERROR","TEST_RUN_FAILURE"):
    key += "<SPAN class=\"%s\">%s</SPAN>\n"%(category_class_names[category],
                                          category_display_names[category])
key += "</P>"


table_text=""

print key
print "<TABLE class=\"fixed\">"

#print "<THEAD>"
#print "<TR><TH></TH>"
uor_headers = ""
for uor in sorted_uors:
    uor_headers += "<TH COLSPAN=3>%s</TH>"%(uor)
#print uor_headers
#print "</TR>"
#print "</THEAD>"

print "<TBODY>"
for uplid in sorted(uplids):
    print "<TR><TH>%s</TH>%s<TR>"%(uplid,uor_headers)
    for ufid in sorted(ufids):
        if not ((uplid in uplid_ufid_combos) and (ufid in uplid_ufid_combos[uplid])):
            continue
        print "<TR>"
        print "<TD>%s</TD>"%(ufid)
        for uor in sorted_uors:
            inner_result=results[uor][uplid][ufid]
            category_results={}

            #for category in ("BUILD_WARNING","BUILD_ERROR","TEST_WARNING","TEST_ERROR","TEST_RUN_FAILURE"):
            for category in ("BUILD_ERROR","TEST_ERROR","TEST_RUN_FAILURE"):
                print "<TD class=\"TD-%s\">"%category_class_names[category]
                if category in inner_result:
                    url = "results.py?db=%s;uor=%s;uplid=%s;ufid=%s;category=%s"%(
                                db(),
                                uor,
                                uplid,
                                ufid,
                                category
                            )
                    print "<A HREF=\"%s\" TARGET=\"_blank\">" % url
                    print "<SPAN CLASS=%s>%d</SPAN>\n"%(
                            category_class_names[category],
                            int(inner_result[category]),
                            )
                    print "</A>"

                print "</TD>"
        print "</TR>"

print "</TBODY>"


print "<TFOOT>"
print "<TR><TH></TH>"
print uor_headers
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

