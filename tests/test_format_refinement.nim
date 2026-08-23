import std/unittest
import vexterlib

proc word(data: var seq[byte], value: int) =
  data.add byte(value); data.add byte(value shr 8)

proc dword(data: var seq[byte], value: uint32) =
  data.add byte(value); data.add byte(value shr 8)
  data.add byte(value shr 16); data.add byte(value shr 24)

proc crc32(data: openArray[byte]): uint32 =
  result = 0xffffffff'u32
  for value in data:
    result = result xor uint32(value)
    for bit in 0 ..< 8:
      result = (result shr 1) xor
        (if (result and 1) != 0: 0xedb88320'u32 else: 0'u32)
  result = result xor 0xffffffff'u32

proc storedZip(name, contents: string): seq[byte] =
  var payload: seq[byte]
  for value in contents: payload.add byte(value)
  let checksum = crc32(payload)
  result.dword(0x04034b50'u32)
  result.word(20); result.word(0x800); result.word(0)
  result.word(0); result.word(0); result.dword(checksum)
  result.dword(uint32(payload.len)); result.dword(uint32(payload.len))
  result.word(name.len); result.word(0)
  for value in name: result.add byte(value)
  result.add payload
  let centralOffset = result.len
  result.dword(0x02014b50'u32)
  result.word(20); result.word(20); result.word(0x800); result.word(0)
  result.word(0); result.word(0); result.dword(checksum)
  result.dword(uint32(payload.len)); result.dword(uint32(payload.len))
  result.word(name.len); result.word(0); result.word(0)
  result.word(0); result.word(0); result.dword(0); result.dword(0)
  for value in name: result.add byte(value)
  let centralLength = result.len - centralOffset
  result.dword(0x06054b50'u32)
  result.word(0); result.word(0); result.word(1); result.word(1)
  result.dword(uint32(centralLength)); result.dword(uint32(centralOffset))
  result.word(0)

suite "format carrier refinement":
  test "parsed ZIP carriers are delegated once and retained in derivations":
    let data = storedZip("profile.marker", "semantic-package")
    var seenCarrier: VextParsedContainer
    var profileCalls, nestedCalls: int
    let profile = VextFormatRefiner(typeId: "test.zip-profile",
      carrierTypeId: ZipArchiveTypeId,
      probe: proc(filename: string, bytes: openArray[byte],
          carrier: VextParsedContainer): VextRefinementMatch =
        inc profileCalls
        seenCarrier = carrier
        let archive = parsedValue[ZipArchive](carrier, vhkZip)
        if archive.entries.len == 1 and
            archive.entries[0].name == "profile.marker":
          result = VextRefinementMatch(confidence: vdcCertain,
            evidence: @[VextDetectionEvidence(
              description: "synthetic package marker is present")],
            parsed: VextParsedValue[string](kind: vhkZip, value: "profile")))
    let nested = VextFormatRefiner(typeId: "test.profile-leaf",
      carrierTypeId: "test.zip-profile",
      probe: proc(filename: string, bytes: openArray[byte],
          carrier: VextParsedContainer): VextRefinementMatch =
        inc nestedCalls
        if parsedValue[string](carrier, vhkZip) == "profile":
          result = VextRefinementMatch(confidence: vdcProbable,
            evidence: @[VextDetectionEvidence(
              description: "synthetic nested profile is valid")],
            parsed: VextParsedValue[int](kind: vhkZip, value: 1)))
    let refiners = @[profile, nested]
    let detected = detectParsedFormatsWith("package.zip", data, refiners)
    check detected.len == 3
    check detected[0].candidate.typeId == "test.profile-leaf"
    check detected[1].candidate.typeId == "test.zip-profile"
    check detected[2].candidate.typeId == ZipArchiveTypeId
    check detected[0].candidate.derivation.stages.len == 3
    check detected[0].candidate.derivation.stages[0].typeId == ZipArchiveTypeId
    check detected[0].candidate.derivation.stages[2].typeId == "test.profile-leaf"
    check seenCarrier == detected[2].parsed
    check profileCalls == 1
    check nestedCalls == 1

    profileCalls = 0
    let forcedCarrier = forceFormatWith("package.zip", data,
      ZipArchiveTypeId, refiners)
    check forcedCarrier.candidate.derivation.stages.len == 1
    check profileCalls == 0
    let forcedProfile = forceFormatWith("package.zip", data,
      "test.zip-profile", refiners)
    check forcedProfile.candidate.derivation.stages.len == 2
    check profileCalls == 1

    let forcedLeaf = forceFormatWith("package.zip", data,
      "test.profile-leaf", refiners)
    check forcedLeaf.candidate.derivation.stages.len == 3
    check forcedLeaf.candidate.derivation.stages[1].typeId ==
      "test.zip-profile"

    let semanticHandler = VextFormatHandler(typeId: "test.zip-profile",
      kind: vhkZip, carrierTypeId: ZipArchiveTypeId)
    expect Defect:
      discard semanticHandler.parse(data)

  test "failed package profiles leave a generic ZIP candidate":
    let data = storedZip("ordinary.txt", "ordinary")
    let profile = VextFormatRefiner(typeId: "test.zip-profile",
      carrierTypeId: ZipArchiveTypeId,
      probe: proc(filename: string, bytes: openArray[byte],
          carrier: VextParsedContainer): VextRefinementMatch = discard)
    let detected = detectParsedFormatsWith("ordinary.zip", data, @[profile])
    check detected.len == 1
    check detected[0].candidate.typeId == ZipArchiveTypeId
    expect ValueError:
      discard forceFormatWith("ordinary.zip", data, "test.zip-profile",
        @[profile])
