#!/usr/bin/python

import cgi
import glob
import os
import pprint
import sqlite3
import sys

# Enable CGI debugging output
import cgitb
cgitb.enable()

search_dir = "/web_data/db/"
files = filter(os.path.isfile, glob.glob(search_dir + "*"))
files.sort(key=lambda x: os.path.getmtime(x))

db = files[-1]

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
        "build_err" :       ["background-color:black;",
                             "color:red;"
                            ],
        "test_warn":        ["background-color:brown;",
                             "color:yellow;"
                            ],
        "test_err"  :       ["background-color:brown;",
                             "color:red;"
                            ],
        "test_fail" :       ["background-color:brown;",
                             "color:orange;"
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

print "Content-Type: text/html"
print
print "<HTML>"
print "<HEAD>"
print "<TITLE>Results from %s</TITLE>"%(db)

print "<STYLE>"
print """
.default {
    background-color: black;
    color:            white;
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
print "<P>"
for category in sorted(category_names):
    print "<span class=\"%s\">%s</span>"%(short_category_names[category],
                                          category)
print "</P>"
print "<TABLE>"

print "<THEAD>"
print "<TR><TD COLSPAN=2>"
for uor in sorted_uors:
    print "<TH>%s</TH>"%(uor)
print "</TR>"
print "</THEAD>"

print "<TBODY style=\"overflow-y: scroll;\">"
for uplid in sorted(uplids):
    tr_prefix="<TR><TH>%s</TH>"%(uplid)
    for ufid in sorted(ufids):
        if not ((uplid in uplid_ufid_combos) and (ufid in uplid_ufid_combos[uplid])):
            next
        print tr_prefix
        tr_prefix="<TR><TD></TD>"
        print "<TD>%s</TD>"%(ufid)
        for uor in sorted_uors:
            inner_result=results[uor][uplid][ufid]
            print "<TD>"
            category_results={}
            for category in ("BUILD_WARNING","BUILD_ERROR","TEST_WARNING","TEST_ERROR","TEST_RUN_FAILURE"):
                if category in inner_result:
                    print "<SPAN class=%s>%d</SPAN>"%(
                            short_category_names[category],
                            int(inner_result[category]),
                            )
            print "</TD>"
        print "</TR>"

print "</TBODY>"


print "<TFOOT>"
print "<TR><TD COLSPAN=2>"
for uor in sorted_uors:
    print "<TH>%s</TH>"%(uor)
print "</TR>"
print "</TFOOT>"

print "</TABLE>"

print "<P>"
for category in sorted(category_names):
    print "<span class=\"%s\">%s</span>"%(short_category_names[category],
                                          category)
print "</P>"


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

