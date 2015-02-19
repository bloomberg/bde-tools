#!/usr/bin/python

import cgi
import glob
import os
import pprint
import sqlite3
import sys

class Vividict(dict):
    def __missing__(self, key):
        value = self[key] = type(self)()
        return value

print "Content-Type: text/html"
print

search_dir = "/web_data/db/"
files = filter(os.path.isfile, glob.glob(search_dir + "*"))
files.sort(key=lambda x: os.path.getmtime(x))

db = files[-1]

connection = sqlite3.connect(db)
cursor     = connection.cursor()

cursor.execute("SELECT * FROM aggregated_results_at_uor_name_level")

results = Vividict()

for result in cursor.fetchall():
	results[result[0]][result[1]][result[2]][result[3]] = result[4]

#pprint.pprint(results)

