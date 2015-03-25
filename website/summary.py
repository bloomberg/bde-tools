#!/usr/bin/python

import bdetools_website_startup


class Vividict(dict):
    """This class creates a dictionary with perl-like nested hash
       auto-vivification, meaning that attempts to access a non-existent
       subhash will create the missing hash.
    """

    def __missing__(self, key_arg):
        value = self[key_arg] = type(self)()
        return value


category_class_names = {
    "BUILD_WARNING": "build_warn",
    "BUILD_ERROR": "build_err",
    "TEST_WARNING": "test_warn",
    "TEST_ERROR": "test_err",
    "TEST_RUN_FAILURE": "test_fail"
}

category_display_names = {
    "BUILD_WARNING": "BUILD_WARNING",
    "BUILD_ERROR": "BUILD_ERROR",
    "TEST_WARNING": "TEST_WARNING",
    "TEST_ERROR": "TEST_BUILD_ERROR",
    "TEST_RUN_FAILURE": "TEST_RUN_ERROR"
}

styles = {
    "build_warn": ["background-color:black;",
                   "color:orange;"
                   ],
    "build_err": ["background-color:white;",
                  "color:#%02x%02x%02x;" % (49, 168, 0),  # Per abeels email
                  ],
    "TD-build_err": [
        "border-left:  solid 1px #999;",
    ],
    "test_warn": ["background-color:black;",
                  "color:brown;"
                  ],
    "test_err": ["background-color:white;",
                 "color:#%02x%02x%02x;" % (0, 175, 182),  # Per abeels email
                 "font-weight:bold;",
                 ],
    "test_fail": ["background-color:white;",
                  "color:red;",
                  "font-style: italic;",
                  ],
    "TD-test_fail": [
        "padding-right:  5px;",
        "border-right: solid 1px #999;"
    ],
}

uor_ordering = {
    "bsl": 0,
    "bdl": 1,
    "bde": 2,
    "bce": 3,
    "bae": 4,
    "bte": 5,
    "bbe": 6,
    "bsi": 7,
    "e_ipc": 8,
    "a_cdrdb": 9,
    "bap": 10,
    "a_comdb2": 11,
    "a_bdema": 12,
    "a_bteso": 13,
    "a_xercesc": 14,
    "bdx": 15,
    "zde": 16,
}


def uor_key(uor_arg):
    """Return the sorting key for the specified 'uor_arg', in order to allow uors
       to be sorted in a reasonable order.
    """

    if uor_arg not in uor_ordering:
        return 99

    return uor_ordering[uor_arg]


print "<HTML>"
print "<HEAD>"
print "<TITLE>Results from %s - %s</TITLE>" % (bdetools_website_startup.date(), bdetools_website_startup.branch())

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
    print ".%s {" % style
    for formatting in styles[style]:
        print "    %s" % formatting
    print "}"

print "</STYLE>"

print "</HEAD>"
print "<BODY class=\"default\">"

bdetools_website_startup.print_title_row("<H1 align=\"center\">Results from %s - %s </H1>" % (
    bdetools_website_startup.date(), bdetools_website_startup.branch()), "summary.py")

if bdetools_website_startup.db() is None:
    print "<H2>Error initializing summary for %s - %s : %s</H2>" % (
        bdetools_website_startup.date(), bdetools_website_startup.branch(), bdetools_website_startup.error())
    print "</BODY></HTML>"
    bdetools_website_startup.sys.exit(0)

connection = bdetools_website_startup.sqlite3.connect(bdetools_website_startup.db())
cursor = connection.cursor()

cursor.execute("SELECT * FROM aggregated_results_at_uor_name_level")

results = Vividict()
axis_values = Vividict()
uplid_ufid_combos = Vividict()

uors = {}
uplids = {}
ufids = {}
category_names = {}

for result in cursor.fetchall():
    # print result
    results[result[0]][result[1]][result[2]][
        result[3]] = result[4]
    uors[result[0]] = 1
    uplids[result[1]] = 1
    ufids[result[2]] = 1
    uplid_ufid_combos[result[1]][result[2]] = 1
    category_names[result[3]] = 1
    for index in range(0, 4):
        axis_values[index][result[index]] = 1

sorted_uors = sorted(uors, key=uor_key)

# print "<H1 align=\"center\">Results from %s</H1>"%db()
key = "<P>"

for category in ("BUILD_ERROR", "TEST_ERROR", "TEST_RUN_FAILURE"):
    key += "<SPAN class=\"%s\">%s</SPAN>\n" % (category_class_names[category],
                                               category_display_names[category])
key += "</P>"

table_text = ""

print key
print "<TABLE class=\"fixed\">"

uor_headers = ""
for uor in sorted_uors:
    uor_headers += "<TH COLSPAN=3>%s</TH>" % uor

print "<TBODY>"
for uplid in sorted(uplids):
    print "<TR><TH>%s</TH>%s<TR>" % (uplid, uor_headers)
    for ufid in sorted(ufids):
        if not ((uplid in uplid_ufid_combos) and (ufid in uplid_ufid_combos[uplid])):
            continue
        print "<TR>"
        print "<TD>%s</TD>" % ufid

        for uor in sorted_uors:
            inner_result = results[uor][uplid][ufid]
            category_results = {}

            # for category in ("BUILD_WARNING","BUILD_ERROR","TEST_WARNING","TEST_ERROR","TEST_RUN_FAILURE"):
            for category in ("BUILD_ERROR", "TEST_ERROR", "TEST_RUN_FAILURE"):
                print "<TD class=\"TD-%s\">" % category_class_names[category]
                if category in inner_result:
                    url = "results.py?db=%s;uor=%s;uplid=%s;ufid=%s;category=%s" % (
                        bdetools_website_startup.db(),
                        uor,
                        uplid,
                        ufid,
                        category
                    )
                    print "<A HREF=\"%s\" TARGET=\"_blank\">" % url
                    print "<SPAN CLASS=%s>%d</SPAN>\n" % (
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

print "</BODY>"
print "</HTML>"

if False:
    print "################## %s" % "uors"
    bdetools_website_startup.pprint.pprint(uors)
    print "################## %s" % "uplids"
    bdetools_website_startup.pprint.pprint(uplids)
    print "################## %s" % "ufids"
    bdetools_website_startup.pprint.pprint(ufids)
    print "################## %s" % "category_names"
    bdetools_website_startup.pprint.pprint(category_names)
    print "################## %s" % "axis_values"
    bdetools_website_startup.pprint.pprint(axis_values)
