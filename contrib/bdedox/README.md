bdedox
======

Syntax
------

    bdedox <config-file>

Description
-----------

The `bdedox` command generates Doxygen HTML pages from source files documented
according to the BDE style rules.  The command takes a single argument, a
script of shell-variable assignments serving as a "configuration" file (à la
`.profile`).

Note that, because the file is in-sourced, the `config-file` file must be in
your `$PATH` or you must specify `config-file` by a path (either absolute or
relative). For example, if a configuration file named `projectA.cfg` is in the
current directory but `.` is not in your `$PATH`, you must specify:

    bdedox ./projectA.cfg

The configuration file must assign certain shell variables for `bdedox`. The
key values, for which there are no defaults, are:

``` code
BDEDOX_FILELIST=""        # no default
    # Path to readable list of (BDE markup) source pathnames.
    # ROLE: Input to file conversion to Doxygen markup.
    # ROLE: Input to generation of HTML header file.

BDEDOX_DOXYDIR=""         # no default
    # Path to existing writable directory.
    # ROLE: Output for file conversion to Doxygen markup.
    # ROLE: Input HTML file generation.

BDEDOX_HTMLDIR=""         # no default
    # Path to existing writable directory.
    # ROLE: Output for file conversion from Doxygen markup to HTML pages.
```

For example, `projectA.cfg` might contain:

    BDEDOX_FILELIST='projectA_filelist'
    BDEDOX_DOXYDIR='/tmp/doxydir'
    BDEDOX_HTMLDIR='~jdoe/public_html/projectA'

where `projectA_filelist` might contain:

    /public/src/groups/bdl/bdlt/doc/bdlt.txt
    /public/src/groups/bdl/bdlt/bdlt_date.h
    /public/src/groups/bdl/bdlt/bdlt_datetime.h
    /public/src/groups/bdl/bdlt/bdlt_datetimeinterval.h
    /public/src/groups/bdl/bdlt/bdlt_datetimetz.h
    /public/src/groups/bdl/bdlt/bdlt_datetz.h
    /public/src/groups/bdl/bdlt/bdlt_dayofweek.h
    /public/src/groups/bdl/bdlt/bdlt_month.h
    /public/src/groups/bdl/bdlt/bdlt_monthofyear.h
    /public/src/groups/bdl/bdlt/bdlt_time.h
    /public/src/groups/bdl/bdlt/bdlt_timeinterval.h
    /public/src/groups/bdl/bdlt/bdlt_timemachine.h
    /public/src/groups/bdl/bdlt/bdlt_timetz.h

Note that the input can include both package- and group-level documentation
(e.g., `bdlt.txt`) as well as `.h` files. *Every* file listed in the
`$BDEDOX_FILELIST` file must be readable.

`$BDEDOX_HTMLDIR` specifies the directory where the final HTML files are to be
delivered by `doxygen`. The `$BDEDOX_DOXYDIR` specifies a directory to be used
as work-area. It is filled with files in Doxygen-markup created from the BDE
markup-ed source files listed in `$BDEDOX_FILELIST`.

Dependencies
------------

`bdedox` depends on Doxygen 1.7.1.  The `doxygen` executable must be in the
`PATH`.  On recent OS distributions it may be necessary to install Doxygen
1.7.1 manually, and override `PATH` when invoking `bdedox`, to avoid confusion
with the system-supported Doxygen:

    PATH=/opt/doxygen-1.7.1/bin:$PATH ./bdedox ./my-project.cfg

Additional Documentation
------------------------

Other (optional) parameters are described in `bdedox.cfg`, a configuration file
template located in the root directory of this repository.

Sample Configuration
--------------------

A sample configuration file for producing documentation for BDE 3.0.0 is
provided in the `sample` directory, along with a `bash` script to drive the
documentation generation process.

Disclaimer
----------

`bdedox` is legacy software that depends on an outdated version of Doxygen
(version 1.7.1).  While `bdedox` is functional, and is currently used to
produce the documentation for [BDE](http://bloomberg.github.io/bde/), we no
longer maintain the scripts and are actively looking for a modern replacement.
These scripts are provided on an as-is, use-at-your-own-risk basis.
