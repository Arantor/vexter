## Structured metadata attached to containers and resources.

type
  VextMetadataValueKind* = enum
    vmvkInteger
    vmvkString

  VextMetadataValue* = object
    case kind*: VextMetadataValueKind
    of vmvkInteger:
      integerValue*: int
    of vmvkString:
      stringValue*: string

  VextMetadataEntry* = object
    key*: string
    value*: VextMetadataValue

proc integerMetadata*(key: string, value: int): VextMetadataEntry =
  VextMetadataEntry(
    key: key,
    value: VextMetadataValue(kind: vmvkInteger, integerValue: value))

proc stringMetadata*(key, value: string): VextMetadataEntry =
  VextMetadataEntry(
    key: key,
    value: VextMetadataValue(kind: vmvkString, stringValue: value))

