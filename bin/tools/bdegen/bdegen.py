#!/usr/bin/env python

# Author: Chen He (che24@bloomberg.net)
# This file has been adapted from work originally done by Chris Palmer.
#
#    Copyright (C) Bloomberg L.P., 2007
#    All Rights Reserved.
#    Property of Bloomberg L.P. (BLP)
#    This software is made available solely pursuant to the
#    terms of a BLP license agreement which governs its use.

from __future__ import print_function

import sys
import os
import files
import ttengine


def get_template_path(folder, filename):
    templatefolder = os.path.join(os.path.dirname(files.getexecutingpath()),
                                  "templates")
    templatepath = os.path.join(templatefolder, folder, filename)
    return templatepath


def process_template(folder, filename, options):
    templatepath = get_template_path(folder, filename)
    if not os.path.isfile(templatepath):
        print("Error: Cant find template file: ", templatepath)
        sys.exit(1)

    return ttengine.processfile(templatepath, options)


def apply_template(folder, filename, options, outputpath):
    if (os.path.isfile(outputpath)):
        print("INFO: Skipping creation of", outputpath, ": Already exists")
        return

    files.writeline(outputpath, process_template(folder, filename, options))


def create_group(name):
    name = name.lower()
    grouppath = os.path.abspath(name)
    if os.path.exists(grouppath):
        print("Error: Directory already exists: ", grouppath)
        sys.exit(2)
    if len(name) != 3:
        print("Error: Group name must be 3 letters: ", name)
        sys.exit(3)

    groupmetapath = os.path.join(grouppath, "group")
    groupdep = os.path.join(groupmetapath, name + ".dep")
    groupmem = os.path.join(groupmetapath, name + ".mem")
    groupdefs = os.path.join(groupmetapath, name + ".defs")

    files.createdir(grouppath)
    files.createdir(groupmetapath)

    metaoptions = {"GROUP_NAME": name}

    apply_template("group", "group.dep",  metaoptions, groupdep)
    apply_template("group", "group.mem",  metaoptions, groupmem)
    apply_template("group", "group.defs",  metaoptions, groupdefs)


def create_package(name, type_):
    name = name.lower()
    packagepath = os.path.abspath(name)
    if os.path.exists(packagepath):
        print("Error: Directory already exists: ", packagepath)
        sys.exit(1)

    groupname = os.path.basename(os.path.dirname(packagepath))
    packagemetapath = os.path.join(packagepath, 'package')
    packagedep = os.path.join(packagemetapath, name + '.dep')
    packagemem = os.path.join(packagemetapath, name + '.mem')
    packageopts = os.path.join(packagemetapath, name + '.opts')

    files.createdir(packagepath)
    files.createdir(packagemetapath)

    metaoptions = {'GROUP_NAME': groupname,
                   'PACKAGE_NAME': name}
    apply_template('package', 'package.mem',  metaoptions, packagemem)
    apply_template('package', 'package.opts', metaoptions, packageopts)

    if type_ == 'app':
        apply_template('package', 'app_package.dep',  metaoptions, packagedep)
        cppmainpath = os.path.join(packagepath, name + '.m.cpp')
        apply_template('package', 'app_package.m.cpp', metaoptions,
                       cppmainpath)
    else:
        apply_template("package", "package.dep",  metaoptions, packagedep)

        # Update package group mem file
        groupmempath = os.path.join('group', groupname + '.mem')
        if os.path.isfile(groupmempath):
            packages = files.readlines(groupmempath)
            packages.append(name)
            packages.sort()
            files.writelines(groupmempath, packages)
        else:
            print("Warning: Couldn't find group mem file to update: ",
                  groupmempath)


def apply_component_template(type, extension, componentname, metaoptions,
                             is_bsl):
    if len(type) == 0:
        type = "value"

    metaoptions["EXTENSION"] = extension
    if extension != "t.cpp":
        if is_bsl:
            metaoptions["IDENT"] = process_template("component", "bslident" +
                                                    "." + extension,
                                                    metaoptions)
        else:
            metaoptions["IDENT"] = process_template("component", "bslident" +
                                                    "." + extension,
                                                    metaoptions)

    templatename = type + "." + extension
    componentfilename = componentname + "." + extension
    apply_template("component", templatename, metaoptions, componentfilename)
    pass


def create_component(name, type_):
    if type_[0:3] == 'bsl':
        bsl = True
        type_ = type_[3:]
    else:
        bsl = False

    # At least first letter should be uppercase
    name = name[0].upper() + name[1:]

    groupname = os.path.basename(os.path.dirname(os.path.abspath(os.curdir)))
    packagename = os.path.basename(os.path.abspath(os.curdir)).lower()
    componentname = packagename + "_" + name.lower()
    bbempinfout = os.popen('bbempinf -n -e $USER')
    bbempinfstr = bbempinfout.read().rstrip()

    if bbempinfout.close() is None:
        (fullname, email) = bbempinfstr.split(';')
        (firstname, lastname) = map(lambda x: x.title(), fullname.split('|'))
        authorinfo = firstname.title() + " " + lastname.title()
        authorinfo += " (" + email + ")"
    else:
        authorinfo = '<<full name>> (<<email>>)'

    metaoptions = {"GROUP_NAME": groupname,
                   "PACKAGE_NAME": packagename,
                   "COMPONENT_NAME": componentname,
                   "CLASS_NAME": name,
                   "AUTHOR_INFO": authorinfo}

    apply_component_template(type_, "h", componentname, metaoptions, bsl)
    apply_component_template(type_, "cpp", componentname, metaoptions, bsl)
    if bsl:
        apply_component_template("bsl", "t.cpp", componentname, metaoptions,
                                 bsl)
    else:
        apply_component_template("bde", "t.cpp", componentname, metaoptions,
                                 bsl)

    # Update package mem file
    packagemempath = os.path.join("package", packagename + ".mem")
    if os.path.isfile(packagemempath):
        components = files.readlines(packagemempath)
        components.append(componentname)
        components.sort()
        files.writelines(packagemempath, components)
    else:
        print("Warning: Couldn't find package mem file to update: ",
              packagemempath)

usage = '''
Usage: bdegen.py (g|p|c) <name> [type]

Descritions for the first parameter:
    g - group
    p - package
    c - component

(Use `bdegen.py help` to see the full help page)
'''


def main():
    if len(sys.argv) == 2 and sys.argv[1] == 'help':
        readme_path = os.path.join(
            os.path.abspath(os.path.dirname(sys.argv[0])),
            "README.md")
        if os.path.isfile(readme_path):
            with open(readme_path, 'r') as fin:
                print(fin.read())
        sys.exit(1)

    if len(sys.argv) <= 2 or sys.argv[1] == '-h' or sys.argv[1] == '--help':
        print(usage)
        sys.exit(1)

    command = sys.argv[1]
    name = sys.argv[2]
    type_ = ''
    if len(sys.argv) > 3:
        type_ = sys.argv[3]

    if len(type_) == 0:
        type_ = 'value'

    if command == 'group' or command == 'g':
        create_group(name)

    elif command == 'package' or command == 'p':
        create_package(name, type_)

    elif command == 'component' or command == 'c':
        create_component(name, type_)

    else:
        print('Error: Unknown item type specified: ', command)
        print("Expected 'group', 'package', or 'component'")
        sys.exit(1)


if __name__ == "__main__":
    main()
