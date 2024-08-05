from __future__ import annotations


def removeprefix(string: str, prefix: str, /) -> str:
    """
    removeprefix Remove the prefix from the beginning of string if it is present.

    Behaves like Python 3.10 str.removeprefix(prefix,/), except that this is not a method.

    :param string: The string to possibly modify.
    :type string: str
    :param prefix: The prefix to use in str.starswith(prefix,/) and remove.
    :type prefix: str
    :return: Either the original string or with the prefix removed if it was present.
    :rtype: str
    """
    if string.startswith(prefix):
        return string[len(prefix) :]
    return string


def removesuffix(string: str, suffix: str, /) -> str:
    """
    removesuffix Remove the suffix from the end of the string if it is present.

    Behaves like Python 3.10 str.removesuffix(prefix,/), except that this is not a method.

    :param string: The string to possibly modify.
    :type string: str
    :param suffix: The prefix to use in str.endswith(suffix,/) and remove.
    :type suffix: str
    :return: Either the original string or with the suffix removed if it was present.
    :rtype: str
    """
    if string.endswith(suffix):
        return string[: -len(suffix)]
    return string
