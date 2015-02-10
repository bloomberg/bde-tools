#!/opt/bb/bin/python

import sys      # argv
import os       # path.getsize
import sqlite3

db = sys.argv[1]
connection = sqlite3.connect(db)
cursor  = connection.cursor()

sys.argv = sys.argv[2:]

def dbsetup(cursor):
    """Initialize the database in the specified 'cursor', creating tables and
    indices if necessary."""

    tables = [
            [ "build_errors",
                [ "pkg_group",  "TEXT" ],
                [ "component",  "TEXT" ],
                [ "diagnostics", "TEXT" ],
            ],

            [ "build_warnings",
                [ "pkg_group",  "TEXT" ],
                [ "component",  "TEXT" ],
            ],

            [ "test_failures",
                [ "pkg_group",  "TEXT" ],
                [ "component",  "TEXT" ],
                [ "diagnostics", "TEXT" ],
            ],

            [ "components_built_ok",
                [ "pkg_group",  "TEXT" ],
                [ "component",  "TEXT" ],
            ],

            [ "components_tested_ok",
                [ "pkg_group",  "TEXT" ],
                [ "component",  "TEXT" ],
                [ "diagnostics", "TEXT" ],
            ],

    ]

    for table in tables:
        column_text="\n"
        comma=""
        for column in table[1:]:
            column_text+="  %1s  %-20s   %-s\n"%(comma, column[0], column[1])
            comma=","

        create_statement="CREATE TABLE IF NOT EXISTS %s (%s)"%(table[0], column_text)

        #print(create_statement)
        cursor.execute(create_statement);


def process(text):
    """Load the specified 'text' into the current database context.
    """





def load(file):
    """Load the specified 'file' into the current database context.
    """

    text=""

    size = os.path.getsize(file)

    with open(file, "rb") as fh:
        text = fh.read(size)
        print("Read %s bytes from %s"%(size, file))

    process(text)

dbsetup(cursor)

for file in sys.argv[1:]:
    load(file)

