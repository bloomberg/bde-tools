#!/opt/bb/bin/python

import sys      # argv
import os       # path.getsize
import sqlite3

db = sys.argv[1]
connection = sqlite3.connect(db)
cursor  = connection.cursor()

sys.argv = sys.argv[2:]

# Mapping build uplid/ufid pairs to rowis in the "builds" table.
builds = {}

# Mapping component/build names to rowids in the "components" table.
components = {}

def updateBuildDictionary(uplid, ufid, rowid):
    """Add an uplid/ufid combo to the 'builds' dictionary.
    """

    builds["%s/%s"%(uplid, ufid)] = rowid


def updateComponentDictionary(uplid, ufid, component, rowid):
    """Add an uplid/ufid/component combo to the 'components' dictionary.
    """

    components["%s/%s/%s" % (uplid, ufid, component)] = rowid


def getBuildRowid(uplid, ufid):
    """Return the 'rowid' associated with the specified 'uplid/ufid' combo,
       adding it to the 'builds' and database dictionary if necessary.
    """

    key="%s/%s" % (uplid, ufid)

    if key in builds:
        return builds[key]

    insert_command="""
        INSERT INTO builds VALUES (?, ?)
    """

    cursor.execute(insert_command, (uplid, ufid));

    select_command="""
        SELECT rowid FROM builds WHERE uplid=? AND ufid=?
    """

    rowid = cursor.execute(select_command, (uplid, ufid))

    updateBuildDictionary(uplid, ufid, rowid)

    return rowid


def dbsetup(cursor):
    """Initialize the database in the specified 'cursor', creating tables and
    indices if necessary."""

    tables = [
            [ "builds",
                [ "uplid",      "TEXT" ],
                [ "ufid",       "TEXT" ],
                [ "PRIMARY KEY( uplid, ufid )" ],
            ],

            [ "uors",
                [ "uor_name",   "TEXT" ],
                [ "component",  "TEXT" ],
            ],

            [ "components",
                [ "component",  "TEXT" ],
                [ "build",      "INTEGER",  "REFERENCES builds(rowid)" ],
                [ "PRIMARY KEY( component, build )" ],
            ],

            [ "build_errors",
                [ "component_id", "INTEGER", "REFERENCES components(rowid)" ],
                [ "diagnostics",  "TEXT" ],
            ],

            [ "build_warnings",
                [ "component_id", "INTEGER", "REFERENCES components(rowid)" ],
                [ "diagnostics",  "TEXT" ],
            ],

            [ "test_failures",
                [ "component_id", "INTEGER", "REFERENCES components(rowid)" ],
                [ "diagnostics", "TEXT" ],
            ],

            [ "components_built_ok",
                [ "component_id", "INTEGER", "REFERENCES components(rowid)" ],
            ],

            [ "components_tested_ok",
                [ "component_id", "INTEGER", "REFERENCES components(rowid)" ],
                [ "diagnostics", "TEXT" ],
            ],
    ]

    for table in tables:
        column_text="\n"
        comma=""
        for column in table[1:]:
            column_text+="  %1s  %-20s\n"%(comma, "\t".join(column))
            comma=","

        create_statement="CREATE TABLE IF NOT EXISTS %s (%s)"%(table[0], column_text)

        #print(create_statement)
        cursor.execute(create_statement);

        builds_query="""
            SELECT rowid, uplid, ufid FROM builds
        """

        for rowid, uplid, ufid in cursor.execute(builds_query):
            updateBuildDictionary(uplid, ufid, rowid)

        components_query="""
            SELECT     a.rowid, b.updlid, b.ufid, a.component
            FROM       components AS a,
                       builds     AS b
            WHERE      a.build = b.rowid
        """

        for rowid, uplid, ufid, component in cursor.execute(""):
            updateComponentDictionary(uplid, ufid, component, rowid)



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

