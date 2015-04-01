import collections

MsvcVersion = collections.namedtuple(
    'MsvcVersion',
    ['cl_version', 'vs_year', 'vs_version'])

versions = [
    MsvcVersion('18.00', '2013', '12.0'),
    MsvcVersion('17.00', '2012', '11.0'),
    MsvcVersion('16.00', '2010', '10.0')
]
