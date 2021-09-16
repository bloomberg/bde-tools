"""Provides a list of valid visual studio versions.
"""

import collections

MsvcVersion = collections.namedtuple(
    'MsvcVersion',
    ['product_name', 'product_version'])

versions = [
    MsvcVersion('Visual Studio 2019', '16'),
    MsvcVersion('Visual Studio 2022', '17'),
    MsvcVersion('Visual Studio 2017', '15'),
    MsvcVersion('Visual Studio 2015', '14'),
    MsvcVersion('Visual Studio 2013', '12')
]
