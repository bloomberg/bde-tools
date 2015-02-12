#!/opt/bb/bin/python

import sys      # argv
import os       # path.getsize
import sqlite3
import re

db = sys.argv[1]
connection = sqlite3.connect(db)
cursor  = connection.cursor()

sys.argv = sys.argv[2:]

# Mapping build uplid/ufid pairs to rowis in the "builds" table.
builds = {}

# Mapping component/build names to rowids in the "components" table.
components = {}

def getBuildKey(uplid, ufid):
    """Build up a dictionary key from the specified 'uplid/ufid'.
    """

    return "%s/%s" % (uplid, ufid)

def getComponentKey(uplid, ufid, component_name):
    """Build up a component key from the specified 'uplid/ufid/component_name'.
    """

    return "%s/%s/%s" % (uplid, ufid, component_name)


def updateBuildDictionary(uplid, ufid, rowid):
    """Add an existing uplid/ufid combo to the 'builds' dictionary.
    """

    builds[getBuildKey(uplid, ufid)] = rowid


def updateComponentDictionary(uplid, ufid, component_name, component):
    """Add an existing uplid/ufid/component_name combo to the 'components' dictionary.
    """

    components[getComponentKey(uplid, ufid, component_name)] = component


def getBuildRowid(uplid, ufid):
    """Return the 'rowid' associated with the specified 'uplid/ufid' combo,
       adding it to the 'builds' and database dictionary if necessary.
    """

    key=getBuildKey(uplid, ufid)

    if key in builds:
        return builds[key]

    insert_command="""
        INSERT INTO builds VALUES (NULL, ?, ?)
    """

    cursor.execute(insert_command, (uplid, ufid));

    updateBuildDictionary(uplid, ufid, cursor.lastrowid)

    return rowid

def getComponentRowid(uplid, ufid, component_name):
    """Return the 'rowid' associtate with the specified 'uplid/ufid/component_name'
       combo, adding it to the 'components' and 'builds' dictionaries and
       databases if necessary.
    """

    key=getComponentKey(uplid, ufid, component_name);

    if key in components:
        return components[key]

    buildRowid = getBuildRowid(uplid, ufid)

    insert_command="""
        INSERT INTO components VALUES (NULL, ?, ?)
    """

    cursor.execute(insert_command, (component_name, buildRowid));

    updateComponentDictionary(uplid, ufid, component_name, cursor.lastrowid)

    return rowid


def dbsetup(cursor):
    """Initialize the database in the specified 'cursor', creating tables and
    indices if necessary."""

    tables = [
            [ "builds",
                [ "build",      "INTEGER PRIMARY KEY" ],
                [ "uplid",      "TEXT" ],
                [ "ufid",       "TEXT" ],
            ],

            [ "uors",
                [ "uor",             "INTEGER PRIMARY KEY" ],
                [ "uor_name",        "TEXT" ],
                [ "component_name",  "TEXT" ],
            ],

            [ "components",
                [ "component",       "INTEGER PRIMARY KEY" ],
                [ "component_name",  "TEXT" ],
                [ "build",           "INTEGER",  "REFERENCES builds(build)" ],
            ],

            [ "build_errors",
                [ "component",    "INTEGER", "REFERENCES components(component)" ],
                [ "diagnostics",  "TEXT" ],
            ],

            [ "build_warnings",
                [ "component",    "INTEGER", "REFERENCES components(component)" ],
                [ "diagnostics",  "TEXT" ],
            ],

            [ "test_build_errors",
                [ "component",    "INTEGER", "REFERENCES components(component)" ],
                [ "diagnostics",  "TEXT" ],
            ],

            [ "test_build_warnings",
                [ "component",    "INTEGER", "REFERENCES components(component)" ],
                [ "diagnostics",  "TEXT" ],
            ],

            [ "test_run_failures",
                [ "component",   "INTEGER", "REFERENCES components(component)" ],
                [ "diagnostics", "TEXT" ],
            ],

            [ "components_built_ok",
                [ "component", "INTEGER", "REFERENCES components(component)" ],
            ],

            [ "components_test_built_ok",
                [ "component", "INTEGER", "REFERENCES components(component)" ],
            ],

            [ "components_tested_ok",
                [ "component", "INTEGER", "REFERENCES components(component)" ],
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
        SELECT build, uplid, ufid FROM builds
    """

    for build, uplid, ufid in cursor.execute(builds_query):
        updateBuildDictionary(uplid, ufid, build)

    components_query="""
        SELECT     a.component, b.uplid, b.ufid, a.component_name
        FROM       components AS a
        INNER JOIN builds     AS b
        ON         a.build = b.build
    """

    for component, uplid, ufid, component_name in cursor.execute(""):
        updateComponentDictionary(uplid, ufid, component_name, component)


def namesplit(name):
    """Split the specified 'name' into its date, group, uplid, and host
    components.
    """

    pattern = re.compile("slave(?:\.TEST-RUN)?\.(\d{8})-\d{6}\.([^.]+)\.(.*?)\.(\w+)\.\d+\.log");

    match = pattern.search(name)

    if match is None:
        print "Badly formed filename '%s'"%(name)
        exit(1)

    return { 'date'  : match.group(1),
             'group' : match.group(2),
             'uplid' : match.group(3),
             'host'  : match.group(4),
             }


def process(filename, text):
    """Load the specified 'text' into the current database context.
    """

    fileInfo = nameSplit(filename)

    uplid = fileInfo["uplid"]
    group = fileInfo["group"]
    date  = fileInfo["date"]
    host  = fileInfo["host"]

    diagnostics_by_category  = {}
    diagnostics_by_component = {}





def load(filename):
    """Load the specified 'filename' into the current database context.
    """

    text=""

    size = os.path.getsize(filename)

    with open(filename, "rb") as fh:
        text = fh.read(size)
        print("Read %s bytes from %s"%(size, filename))

    process(filename, text)

dbsetup(cursor)

for file in sys.argv[1:]:
    load(file)

