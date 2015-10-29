#!/usr/bin/python

import bdetools_website_startup

connection = bdetools_website_startup.sqlite3.connect(bdetools_website_startup.db())

# Make connection resistant to invalid utf-8
connection.text_factory = str

cursor = connection.cursor()

bdetools_website_startup.print_title_row("<H1>Results from %s</H1>" % bdetools_website_startup.db(),
                                       "results.py")
print "<H2 align=\"center\">for (%s, %s, %s, %s)</H2>" % (bdetools_website_startup.fieldstore()["uor"].value,
                                                          bdetools_website_startup.fieldstore()["ufid"].value,
                                                          bdetools_website_startup.fieldstore()["uplid"].value,
                                                          bdetools_website_startup.fieldstore()["category"].value)

cursor.execute("""
    SELECT component_name,
           diagnostics
    FROM build_results
    WHERE uor_name=?
          AND ufid=?
          AND uplid=?
          AND category_name=?
""", (bdetools_website_startup.fieldstore()["uor"].value,
      bdetools_website_startup.fieldstore()["ufid"].value,
      bdetools_website_startup.fieldstore()["uplid"].value,
      bdetools_website_startup.fieldstore()["category"].value))

print "<PRE>"

for entry in cursor.fetchall():
    print "".join(entry)
    print "\n======\n"

print "</PRE>"
