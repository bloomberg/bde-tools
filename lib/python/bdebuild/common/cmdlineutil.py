def add_options(grp, opts):
    for opt in opts:
        opt_strings = ['-' + a if len(a) == 1 else '--' + a
                       for a in opt[0]]
        grp.add_option(*opt_strings, **opt[1])
