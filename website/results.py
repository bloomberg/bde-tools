#!/usr/bin/python

import cgi
import glob
import os
import os.path
import pprint
import sqlite3
import re
import sys
from bdetools_website_startup import *

connection = sqlite3.connect(db())
cursor     = connection.cursor()

printTitleRow("<H1 align=\"center\">Results from %s</H1>"%db(), "results.py")
print "<H2 align=\"center\">for (%s, %s, %s, %s)</H2>"%(fieldstore()["uor"].value,
     fieldstore()["ufid"].value,
     fieldstore()["uplid"].value,
     fieldstore()["category"].value)

cursor.execute("""
    SELECT component_name,
           diagnostics
    FROM build_results
    WHERE uor_name=?
          AND ufid=?
          AND uplid=?
          AND category_name=?
""",(fieldstore()["uor"].value,
     fieldstore()["ufid"].value,
     fieldstore()["uplid"].value,
     fieldstore()["category"].value))

print "<PRE>"

for entry in cursor.fetchall():
    print "".join(entry)
    print "\n======\n"

print "</PRE>"

