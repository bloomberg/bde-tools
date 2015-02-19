#!/usr/bin/python

import cgi
import glob
import os
import os.path
import pprint
import sqlite3
import re
import sys

# Enable CGI debugging output
import cgitb
cgitb.enable()

print "Content-Type: text/html"
print

fs = cgi.FieldStorage()

search_dir = "/web_data/db/"

#if re.match("^\s*\.|[\\/|]", fs["db"].value):
#    print "Bad characters in db entry"
#    sys.exit(1)

db = fs["db"].value;

if not (os.path.isfile(db) and os.access(db, os.R_OK)):
    print "Either file is missing or is not readable"
    sys.exit(1)

connection = sqlite3.connect(db)
cursor     = connection.cursor()

print "<H1 align=\"center\">Results from %s</H1>"%db
print "<H2 align=\"center\">for (%s, %s, %s, %s)</H2>"%(fs["uor"].value,
     fs["ufid"].value,
     fs["uplid"].value,
     fs["category"].value)

cursor.execute("""
    SELECT component_name,
           diagnostics
    FROM build_results
    WHERE uor_name=?
          AND ufid=?
          AND uplid=?
          AND category_name=?
""",(fs["uor"].value,
     fs["ufid"].value,
     fs["uplid"].value,
     fs["category"].value))

print "<PRE>"
for entry in cursor.fetchall():
    print "".join(entry)
    print "\n======\n"

print "</PRE>"

