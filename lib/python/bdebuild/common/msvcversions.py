"""Provides a list of valid visual studio versions.
"""

import collections

MsvcVersion = collections.namedtuple(
    'MsvcVersion',
    ['compiler_version', 'product_name', 'product_version'])

versions = [
    MsvcVersion('19.10', 'Visual Studio 2017', '15.0'),
    MsvcVersion('19.00', 'Visual Studio 2015', '14.0'),
    MsvcVersion('18.00', 'Visual Studio 2013', '12.0'),
    MsvcVersion('17.00', 'Visual Studio 2012', '11.0'),
    MsvcVersion('16.00', 'Visual Studio 2010', '10.0'),
    MsvcVersion('15.00', 'Visual Studio 2008', '9.0')
]
