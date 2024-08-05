import itertools
from typing import Any, Callable, Generator, Iterator, MutableSequence, Optional, Sequence, TypeVar

from lib.xtCppParseResults import TestcaseMapping


T = TypeVar("T")


def _filterAndGroup(
    sequence: Sequence[T],
    *,
    keyFunc: Callable[[T], Any],
    filterFunc: Callable[[T], bool] = lambda _: True,
    groupLength: Optional[int] = None,
) -> Generator[Iterator[T], None, None]:
    assert groupLength != 0

    if groupLength is None:

        def groupByFunc(x: T):
            return keyFunc(x)

    else:

        def groupByFunc(x: T):
            return keyFunc(x)[:groupLength]

    return (
        x
        for _, x in itertools.groupby(
            sorted(filter(filterFunc, sequence), key=keyFunc), groupByFunc
        )
    )


def generateTestCaseMappingTable(
    testcasesToPartsMapping: Sequence[TestcaseMapping],
) -> Sequence[str]:

    rv: MutableSequence[str] = []
    rv += [
        r"// +=============================+",
        r"// |   TEST CASE MAPPING TABLE   |",
        r"// +=============================+",
        r"// | Original Test Case Number   |",
        r"// |     +-----------------------+",
        r"// |     | Slice Number          |",
        r"// |     |    +------------------+",
        r"// |     |    | Part Number      |",
        r"// |     |    |    +-------------+",
        r"// |     |    |    | Case Number |",
        r"// |     |    |    | in Part     |",
        r"// +=====+====+====+=====+=======+",
    ]
    for group in _filterAndGroup(
        testcasesToPartsMapping,
        keyFunc=lambda x: (x.originalTestcaseNumberSortWeight, x.sliceNumber),
        groupLength=1,
    ):
        rv.extend(
            f"// | {caseNumMapping.originalTestcaseNumber:3} | {caseNumMapping.sliceText(2)}"
            f" | {caseNumMapping.partNumber:02} | {caseNumMapping.partTestcaseNumber:3} |"
            for caseNumMapping in group
        )
        rv.append("// +-----+----+----+-----+")
    rv[-1] = "// +=====+====+====+=====+"

    return rv


def generatePartMappingTable(
    testcasesToPartsMapping: Sequence[TestcaseMapping], numParts: int
) -> Sequence[str]:
    rv: MutableSequence[str] = []
    rv += [
        r"// +============================+",
        r"// |     PART MAPPING TABLE     |",
        r"// +============================+",
        r"// | Part Number                |",
        r"// |    +-----------------------+",
        r"// |    | Original Case Number  |",
        r"// |    |     +-----------------+",
        r"// |    |     | Slice Number    |",
        r"// |    |     |    +------------+",
        r"// |    |     |    | Part Case  |",
        r"// |    |     |    | Number     |",
        r"// +====+=====+====+=====+======+",
    ]
    for group in _filterAndGroup(
        testcasesToPartsMapping,
        keyFunc=lambda x: (x.partNumber, x.originalTestcaseNumberSortWeight, x.sliceNumber),
        groupLength=1,
    ):
        rv.extend(
            f"// | {caseNumMapping.partNumber:02} | {caseNumMapping.originalTestcaseNumber:3}"
            f" | {caseNumMapping.sliceText(2)} | {caseNumMapping.partTestcaseNumber:3} |"
            for caseNumMapping in group
        )
        rv.append("// +----+-----+----+-----+")
    rv[-1] = "// +====+=====+====+=====+"

    return rv


def generateTestCaseMappingTableForPart(
    testcasesToPartsMapping: Sequence[TestcaseMapping], partNum: int
) -> Sequence[str]:
    rv: MutableSequence[str] = []
    rv += [
        r"// +===========================+",
        r"// | THIS PART's MAPPING TABLE |",
        r"// +===========================+",
        r"// | Original Test Case Number |",
        r"// |     +---------------------+",
        r"// |     | Slice Number        |",
        r"// |     |    +----------------+",
        r"// |     |    |  Case Number   |",
        r"// |     |    |  in Part       |",
        r"// +=====+====+=====+==========+",
    ]
    for group in _filterAndGroup(
        testcasesToPartsMapping,
        keyFunc=lambda x: (x.originalTestcaseNumberSortWeight, x.sliceNumber),
        filterFunc=lambda x: x.partNumber == partNum,
    ):
        rv.extend(
            f"// | {caseNumMapping.originalTestcaseNumber:3} | {caseNumMapping.sliceText(2)}"
            f" | {caseNumMapping.partTestcaseNumber:3} |"
            for caseNumMapping in group
        )
        rv.append("// +-----+----+-----+")
    rv[-1] = "// +=====+====+=====+"

    return rv
