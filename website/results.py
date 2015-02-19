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

# TBD: extract all this common stuff out of results and summary.
print "Content-Type: text/html"
print

fs = cgi.FieldStorage()

search_dir = "/web_data/db/"
files = filter(os.path.isfile, glob.glob(search_dir + "*"))
files.sort()   # (key=lambda x: os.path.getctime(x))

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

if not (re.match("^/web_data/db/[^/]+\.db$", db) or os.getuid()==os.stat(db).st_uid):
    print "db value %s is invalid"%db
    sys.exit(1)

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

