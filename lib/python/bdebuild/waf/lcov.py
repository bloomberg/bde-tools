"""Utilities using lcov to generate test coverage reports.
"""

import os
import subprocess

from waflib import Utils
from waflib import Logs


def generate_coverage_report(obj_dirs, src_dirs, repo_root, bld_dir, tmp_dir,
                             out_dir, lcov_exe, genhtml_exe):
    """Generate an HTML coverage report using lcov.

    The test coverage of each source file include the transitive coverage of
    all test drivers ran.  This means the coverage of a particular component
    doesn't include just the coverage from its own test drivers, but from all
    other test drivers that has been ran as well.

    To see the coverage of an individual test driver, generate a report for
    just that test driver itself.

    This limitation is partly due to the way ``lcov`` works.  ``lcov`` can only
    filter based on a directory level, so getting a non-transitive report would
    involve moving the coverage data files manually for each test driver.

    This function was originally designed to run lcov in parallel across all
    packages.  Unfortunately running lcov for each package in parallel is not
    possible, because lcov opens all intrumented files in all packages
    regardless of whether its needed for the output, which results in random
    file open errors for some lcov instances.

    Args:
        obj_dirs (list of str): Paths to object file directories.
        src_dirs (list of str): Paths to source file directories.
        repo_root (src): Path to the root of the repo.
        bld_dir (str): Path to the root build output directory.
        tmp_dir (str): Path to directory to hold tempory trace files.
        out_dir (str): Path to directory to hold the generated html report.
        lcov_exe (list): The lcov command to use.
        genhtml_exe (int): The genhtml command to use.

    Returns:
        True if successful

    """

    assert(len(obj_dirs) == len(src_dirs))
    num_packages = len(obj_dirs)
    args_list_list = []
    lcov_exe += ['--quiet', '--no-checksum', '--no-external', '-b', bld_dir]

    p = 0
    while p < num_packages:
        obj_dir = obj_dirs[p]
        src_dir = src_dirs[p]
        p += 1
        package_name = os.path.basename(src_dir)

        base_tracefile = os.path.join(tmp_dir, package_name + '_base.info')
        run_tracefile = os.path.join(tmp_dir, package_name + '_run.info')
        comb_tracefile = os.path.join(tmp_dir, package_name + '_comb.info')
        filt_tracefile = os.path.join(tmp_dir, package_name + '_filt.info')

        loc_d = ['-d', obj_dir, '-d', src_dir]

        lcov_base_cmd = lcov_exe + loc_d + [
            '-c', '-i', '-o', base_tracefile
        ]
        lcov_run_cmd = lcov_exe + loc_d + [
            '-c', '-o', run_tracefile
        ] + loc_d
        lcov_comb_cmd = lcov_exe + [
            '-a', base_tracefile, '-a', run_tracefile,
            '-o', comb_tracefile
        ]
        lcov_filt_cmd = lcov_exe + [
            '--remove', comb_tracefile, '*.t.cpp',
            '-o', filt_tracefile
        ]

        cmd_descs = [
            (lcov_base_cmd,
             '%s: Building baseline trace file' % package_name),
            (lcov_run_cmd,
             '%s: Building test-run trace file' % package_name),
            (lcov_comb_cmd,
             '%s: Combining trace files' % package_name),
            (lcov_filt_cmd,
             '%s: Filtering trace file' % package_name)
        ]
        args_list_list.append([package_name, cmd_descs, filt_tracefile])

    Logs.pprint('CYAN', 'Generating Coverage Report')
    p = 0
    total = num_packages * 4 + 1
    tracefiles = []
    failed_packages = []
    empty_packages = []
    while p < num_packages:
        args = args_list_list[p]
        package_name = args[0]
        cmd = args[1]
        desc = args[2]
        file_ = _do_package(cmd, desc, p * 4 + 1, total)
        if not file_:
            Logs.pprint('RED', 'lcov failed for package "%s". '
                        'Ignoring package...' % package_name)
            failed_packages.append(package_name)
        elif os.stat(file_).st_size == 0:
            Logs.pprint('RED', 'Trace file is empty for package "%s". '
                        'Ignoring package...' % package_name)
            empty_packages.append(package_name)
        else:
            tracefiles.append(file_)
        p += 1

    if not tracefiles:
        Logs.pprint('RED', 'No valid trace files.')
        return False

    genhtml_cmd = genhtml_exe + [
        '--function-coverage', '-t', 'Coverage Test Results',
        '-p', repo_root,
        '-o', out_dir
    ] + [t for t in tracefiles]
    ret = _run_cmd(genhtml_cmd, 'Generating html pages', total, total)
    if ret != 0:
        return False

    if empty_packages or failed_packages:
        Logs.pprint('CYAN', 'Ignored Packages')
        for package in sorted(empty_packages):
            Logs.pprint('YELLOW', '  ' + package + ' (empty)')
        for package in sorted(failed_packages):
            Logs.pprint('RED', '  ' + package + ' (failed)')

    Logs.pprint('CYAN', 'Generated Report')
    Logs.pprint('YELLOW', '  ' + os.path.join(out_dir, 'index.html'))
    return True


def _run_cmd(cmd, desc, begin_count, total_count):
    msg = '[%d/%d] %s%s%s' % (begin_count, total_count,
                              Logs.colors.YELLOW,
                              desc,
                              Logs.colors.NORMAL)
    Logs.info(msg, extra={'c1': '', 'c2': ''})
    Logs.debug('lcov: %s' % cmd)
    p = subprocess.Popen(cmd,
                         stdout=Utils.subprocess.PIPE,
                         stderr=Utils.subprocess.PIPE)

    (out, err) = p.communicate()
    ret = p.returncode
    if ret != 0:
        if out or err:
            msg = '' + out + err
            Logs.pprint('RED', 'lcov error, cmd: %s error msg: %s' %
                        (cmd, msg))
    return ret


def _do_package(cmd_descs, expected_out, begin_count, total_count):
    for cmd_desc in cmd_descs:
        cmd = cmd_desc[0]
        ret = _run_cmd(cmd, cmd_desc[1], begin_count, total_count)
        begin_count += 1
        if ret != 0:
            return None

    if os.path.exists(expected_out):
        return expected_out
    else:
        return None
