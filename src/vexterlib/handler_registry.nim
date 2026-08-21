## Registry of input formats understood by the operations layer.
##
## Detection remains evidence-based and may return several candidates.  This
## registry is the authoritative bridge from a stable type identifier to the
## validation and inspection implementation for that format.

import ./containers/[amiga_8svx, amiga_16sv, amiga_acbm, amiga_adf, amiga_anim,
  amiga_dms, amiga_iff, amiga_ilbm, amiga_workbench_icon, amos_bank,
  amos_bank_set, amos_program, amos_sprite_icon_bank, bmp, gif_container, pcx,
  png_container, wav, zip_archive, zx_spectrum_screen_dump,
  zx_spectrum_snapshot, zx_spectrum_tap]
type
  VextHandlerKind* = enum
    vhkWorkbenchIcon
    vhkAmigaAcbm
    vhkAmiga8svx
    vhkAmiga16sv
    vhkAmigaAdf
    vhkAmigaDms
    vhkAmigaAnim
    vhkAmigaIlbm
    vhkAmigaIff
    vhkBmp
    vhkDib
    vhkPng
    vhkGif
    vhkPcx
    vhkWav
    vhkZip
    vhkAmosProgram
    vhkAmosBankSet
    vhkAmosBank
    vhkAmosSpriteBank
    vhkAmosIconBank
    vhkZxSpectrumScreen
    vhkZxSpectrumSnapshot
    vhkZxSpectrumTap

  VextFormatHandler* = object
    typeId*: string
    kind*: VextHandlerKind

const FormatHandlers* = [
  VextFormatHandler(typeId: AmigaWorkbenchIconTypeId, kind: vhkWorkbenchIcon),
  VextFormatHandler(typeId: AmigaAcbmTypeId, kind: vhkAmigaAcbm),
  VextFormatHandler(typeId: Amiga8svxTypeId, kind: vhkAmiga8svx),
  VextFormatHandler(typeId: Amiga16svTypeId, kind: vhkAmiga16sv),
  VextFormatHandler(typeId: AmigaAdfTypeId, kind: vhkAmigaAdf),
  VextFormatHandler(typeId: AmigaDmsTypeId, kind: vhkAmigaDms),
  VextFormatHandler(typeId: AmigaAnimTypeId, kind: vhkAmigaAnim),
  VextFormatHandler(typeId: AmigaIlbmTypeId, kind: vhkAmigaIlbm),
  VextFormatHandler(typeId: AmigaIffTypeId, kind: vhkAmigaIff),
  VextFormatHandler(typeId: BmpTypeId, kind: vhkBmp),
  VextFormatHandler(typeId: DibTypeId, kind: vhkDib),
  VextFormatHandler(typeId: PngTypeId, kind: vhkPng),
  VextFormatHandler(typeId: GifTypeId, kind: vhkGif),
  VextFormatHandler(typeId: PcxTypeId, kind: vhkPcx),
  VextFormatHandler(typeId: WavTypeId, kind: vhkWav),
  VextFormatHandler(typeId: ZipArchiveTypeId, kind: vhkZip),
  VextFormatHandler(typeId: AmosProgramTypeId, kind: vhkAmosProgram),
  VextFormatHandler(typeId: AmosBankSetTypeId, kind: vhkAmosBankSet),
  VextFormatHandler(typeId: AmosBankTypeId, kind: vhkAmosBank),
  VextFormatHandler(typeId: AmosSpriteBankTypeId, kind: vhkAmosSpriteBank),
  VextFormatHandler(typeId: AmosIconBankTypeId, kind: vhkAmosIconBank),
  VextFormatHandler(typeId: ZxSpectrumScreenDumpTypeId,
    kind: vhkZxSpectrumScreen),
  VextFormatHandler(typeId: ZxSpectrumSnapshotTypeId,
    kind: vhkZxSpectrumSnapshot),
  VextFormatHandler(typeId: ZxSpectrumTapTypeId, kind: vhkZxSpectrumTap)
]

proc formatHandler*(typeId: string): ptr VextFormatHandler =
  ## Returns the registered handler for `typeId`, or nil when unsupported.
  for index in 0 .. FormatHandlers.high:
    if FormatHandlers[index].typeId == typeId:
      return unsafeAddr FormatHandlers[index]

proc validate*(handler: VextFormatHandler, data: openArray[byte]) =
  ## Structurally validates input selected explicitly by a caller.
  case handler.kind
  of vhkWorkbenchIcon: discard parseWorkbenchIcon(data)
  of vhkAmigaAcbm: discard parseAmigaAcbm(data)
  of vhkAmiga8svx: discard parseAmiga8svx(data)
  of vhkAmiga16sv: discard parseAmiga16sv(data)
  of vhkAmigaAdf: discard parseAmigaAdf(data)
  of vhkAmigaDms: discard parseAmigaDms(data)
  of vhkAmigaAnim: discard parseAmigaAnim(data)
  of vhkAmigaIlbm: discard parseAmigaIlbm(data)
  of vhkAmigaIff: discard parseAmigaIff(data)
  of vhkBmp: discard parseBmp(data)
  of vhkDib: discard parseDib(data)
  of vhkPng: discard parsePng(data)
  of vhkGif: discard parseGif(data)
  of vhkPcx: discard parsePcx(data)
  of vhkWav: discard parseWav(data)
  of vhkZip: discard parseZipArchive(data)
  of vhkAmosProgram: discard parseAmosProgram(data)
  of vhkAmosBankSet: discard parseAmosBankSet(data)
  of vhkAmosBank: discard parseAmosBank(data)
  of vhkAmosSpriteBank, vhkAmosIconBank:
    let bank = parseAmosSpriteIconBank(data)
    if bank.amosSpriteIconBankTypeId != handler.typeId:
      raise newException(ValueError,
        "AMOS bank identifier does not match the selected format")
  of vhkZxSpectrumScreen:
    if not isZxSpectrumScreenDump(data):
      raise newException(ValueError,
        "ZX Spectrum screen dump must contain exactly 6912 bytes")
  of vhkZxSpectrumSnapshot:
    if not isZxSpectrumSnapshotSize(data.len):
      raise newException(ValueError,
        "ZX Spectrum snapshot must contain exactly 49179, 131103, or 147487 bytes")
  of vhkZxSpectrumTap:
    if not isZxSpectrumTap(data):
      raise newException(ValueError, "invalid ZX Spectrum TAP container")
