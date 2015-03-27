#!/opt/bb/bin/python -u

import sys  # argv
import os  # path.getsize
import sqlite3
import re

db = sys.argv[1]
connection = sqlite3.connect(db)
cursor = connection.cursor()

sys.argv = sys.argv[0:1] + sys.argv[2:]

# Mapping build uplid/ufid pairs to build ids in the "builds" table.
builds = {}

# Mapping component/build names to component ids in the "components" table.
components = {}

# Mapping uor_name/component_names to uor ids in the "uors" table
uors = {}


def get_build_key(uplid, ufid):
    """Build up a dictionary key from the specified 'uplid/ufid'.
    """

    return "%s/%s" % (uplid, ufid)


def get_component_key(uplid, ufid, component_name):
    """Build up a component key from the specified 'uplid/ufid/component_name'.
    """

    return "%s/%s/%s" % (uplid, ufid, component_name)


def get_uor_key(uor_name, component_name):
    """Build up a UOR key from the specified "uor_name/component_name".
    """

    return "%s/%s" % (uor_name, component_name)


def update_build_dictionary(uplid, ufid, rowid):
    """Add an existing uplid/ufid combo to the 'builds' dictionary.
    """

    builds[get_build_key(uplid, ufid)] = rowid


def update_component_dictionary(uplid, ufid, component_name, component):
    """Add an existing uplid/ufid/component_name combo to the 'components' dictionary.
    """

    components[get_component_key(uplid, ufid, component_name)] = component


def update_uor_dictionary(uor_name, component_name, uor):
    """Add an existing uor to the uors dictionary.
    """

    uors[get_uor_key(uor_name, component_name)] = uor


def get_build_identifier(uplid, ufid):
    """Return the 'rowid' associated with the specified 'uplid/ufid' combo,
       adding it to the 'builds' and database dictionary if necessary.
    """

    key = get_build_key(uplid, ufid)

    if key in builds:
        return builds[key]

    insert_command = """
        INSERT INTO builds VALUES (NULL, ?, ?)
    """

    cursor.execute(insert_command, (uplid, ufid))

    rowid = cursor.lastrowid

    update_build_dictionary(uplid, ufid, rowid)

    return rowid


def get_component_identifier(uplid, ufid, component_name):
    """Return the 'rowid' associated with the specified
       'uplid/ufid/component_name' combo, adding it to the 'components' and
       'builds' dictionaries and databases if necessary.
    """

    key = get_component_key(uplid, ufid, component_name)

    if key in components:
        return components[key]

    buildrowid = get_build_identifier(uplid, ufid)

    insert_command = """
        INSERT INTO components VALUES (NULL, ?, ?)
    """

    cursor.execute(insert_command, (component_name, buildrowid))

    rowid = cursor.lastrowid

    update_component_dictionary(uplid, ufid, component_name, rowid)

    return rowid


def get_uor_identifier(uor_name, component_name):
    """Return the 'uor' identifier associated with the specified
       'uor_name/component_name' combo, adding it to the 'uors' dictionary and
       database if necessary.
    """

    key = get_uor_key(uor_name, component_name)

    if key in uors:
        return uors[key]

    insert_command = """
        INSERT INTO uors VALUES (NULL, ?, ?)
    """

    cursor.execute(insert_command, (uor_name, component_name))

    rowid = cursor.lastrowid

    update_uor_dictionary(uor_name, component_name, rowid)

    return rowid


def add_diagnostics_event(component_name, uplid, ufid, category_name, diagnostics):
    """Add an entry to the 'build_diagnostic_events' diagnostics table.
    """

    component = get_component_identifier(uplid, ufid, component_name)

    insert_command = """
        INSERT INTO build_diagnostic_events VALUES (?, ?, ?)
    """

    cursor.execute(insert_command, (component, category_name, diagnostics))


def dbsetup(cursor_arg):
    """Initialize the database in the specified 'cursor_arg', creating tables and
    indices if necessary."""

    tables = [
        ["builds",
         ["build", "INTEGER PRIMARY KEY"],
         ["uplid", "TEXT"],
         ["ufid", "TEXT"],
         ],

        ["uors",
         ["uor", "INTEGER PRIMARY KEY"],
         ["uor_name", "TEXT"],
         ["component_name", "TEXT"],
         ],

        ["components",
         ["component", "INTEGER PRIMARY KEY"],
         ["component_name", "TEXT"],
         ["build", "INTEGER", "REFERENCES builds(build)"],
         ],

        ["build_diagnostic_events",
         ["component", "INTEGER", "REFERENCES components(component)"],
         ["category_name", "TEXT"],
         ["diagnostics", "TEXT"],
         ],

        ["components_built_ok",
         ["component", "INTEGER", "REFERENCES components(component)"],
         ],

        ["components_test_built_ok",
         ["component", "INTEGER", "REFERENCES components(component)"],
         ],

        ["components_tested_ok",
         ["component", "INTEGER", "REFERENCES components(component)"],
         ["diagnostics", "TEXT"],
         ],

        ["aggregated_results_at_uor_name_level",
         ["uor_name", "TEXT"],
         ["uplid", "TEXT"],
         ["ufid", "TEXT"],
         ["category_name", "TEXT"],
         ["count", "TEXT"],
         ],
    ]

    for table in tables:
        column_text = "\n"
        comma = ""

        for column in table[1:]:
            column_text += "  %1s  %-20s\n" % (comma, "\t".join(column))
            comma = ","

        create_statement = "CREATE TABLE IF NOT EXISTS %s (%s)" % (table[0], column_text)

        # print(create_statement)
        cursor_arg.execute(create_statement)

    cursor_arg.execute("""
            CREATE VIEW IF NOT EXISTS build_results AS
                SELECT uor_name,
                       components.component_name AS component_name,
                       uplid,
                       ufid,
                       category_name,
                       diagnostics
                FROM         builds
                NATURAL JOIN components
                NATURAL JOIN build_diagnostic_events
                INNER JOIN   uors
                ON           components.component_name = uors.component_name
        """)

    indices = [
        ["build_diagnostics_events_component_idx",
         "build_diagnostic_events",
         ["component",
          ],
         ],

        ["components_uor_name_index",
         "components",
         ["component_name",
          ],
         ],

        ["uors_uor_name_index",
         "uors",
         ["uor_name",
          ],
         ],

        ["uors_component_name_index",
         "uors",
         ["component_name",
          ],
         ],

        ["build_diagnostics_events_category_name_idx",
         "build_diagnostic_events",
         ["category_name",
          ],
         ],

        ["components_build_index",
         "components",
         ["build",
          ],
         ],
    ]

    for index in indices:
        column_text = "\n"
        comma = ""

        for column in index[2:]:
            column_text += "  %1s  %-20s\n" % (comma, "\t".join(column))
            comma = ","

        create_statement = "CREATE INDEX IF NOT EXISTS %s ON %s (%s)" % \
                           (index[0], index[1], column_text)

        # print(create_statement)

        cursor_arg.execute(create_statement)

    builds_query = """
        SELECT build, uplid, ufid FROM builds
    """

    for build, uplid, ufid in cursor_arg.execute(builds_query):
        update_build_dictionary(uplid, ufid, build)

    for component, uplid, ufid, component_name in cursor_arg.execute(""):
        update_component_dictionary(uplid, ufid, component_name, component)


def name_split(name):
    """Split the specified 'name' into its date, group, uplid, and host
    components.
    """

    pattern = re.compile("slave(?:\.TEST-RUN)?\.(\d{8})-\d{6}\.([^.]+)\.(.*?)\.(\w+)\.\d+\.log")

    match = pattern.search(name)

    if match is None:
        print "Badly formed filename '%s'" % name
        exit(1)

    return {'date': match.group(1),
            'group': match.group(2),
            'uplid': match.group(3),
            'host': match.group(4),
            }


def process(filename_arg, text):
    """Load the specified 'text' into the current database context.
    """

    fileinfo = name_split(filename_arg)

    uplid = fileinfo["uplid"]
    group = fileinfo["group"]

    text = re.sub("TEST-RUN:\s*\d{6}:", "", text)

    pattern = re.compile(
        "\\[(\\S+) \\((WARNING|ERROR|TEST)\\)\\] <<<<<<<<<<(.*?)>>>>>>>>>>",
        re.S)  # re.S is aka re.DOTALL, so "." matches newlines as well.

    categorynames = {True: dict(WARNING="TEST_WARNING", ERROR="TEST_ERROR", TEST="TEST_RUN_FAILURE"),
                     False: dict(WARNING="BUILD_WARNING", ERROR="BUILD_ERROR", TEST=None)
                     }

    for match in pattern.finditer(text):
        istest = True if re.search("\.t", match.group(1)) else False

        component_name = re.sub(".*[\\\\/]", "", match.group(1))
        component_name = re.sub("\..*", "", component_name)

        # Skip any diagnostics for previous UOR components that
        # failed.
        if not re.match('^%s' % group, component_name):
            continue

        get_uor_identifier(group, component_name)

        category = match.group(2)
        diagnostics = match.group(3)

        substr = text[:match.start()]

        regex_results = re.findall("BDE_WAF_UFID=(\\w+)|ufid\\s+:\\s(\\w+)", substr)

        if regex_results:

            # Use $1 of the LAST match if populated, otherwise use $2
            if len(regex_results[-1][0]):
                ufid = regex_results[-1][0]
            else:
                ufid = regex_results[-1][1]

            add_diagnostics_event(component_name,
                                  uplid,
                                  ufid,
                                  categorynames[istest][category],
                                  diagnostics)
        else:
            print "No match for ufid string in %s..." % substr[:1000]

    connection.commit()


def load(filename_arg):
    """Load the specified 'filename_arg' into the current database context.
    """

    text = ""

    size = os.path.getsize(filename_arg)

    with open(filename_arg, "rb") as fh:
        text = fh.read(size)
        print("Read %s (%d bytes)" % (filename_arg, size))

    process(filename_arg, text)


dbsetup(cursor)

for filename in sys.argv[1:]:
    load(filename)

print "Building aggregates"

cursor.execute("""
        DELETE FROM aggregated_results_at_uor_name_level
        """)
connection.commit()

cursor.execute("""
        INSERT INTO aggregated_results_at_uor_name_level
            (uplid, ufid, uor_name, category_name, count)
            SELECT uplid, ufid, uor_name, category_name, COUNT(*) AS count
            FROM build_results
            GROUP BY uplid, ufid, uor_name, category_name
        """)
connection.commit()

print "Done"
