## Registry of input formats understood by the operations layer.
##
## Detection remains evidence-based and may return several candidates.  This
## registry is the authoritative bridge from a stable type identifier to the
## validation and inspection implementation for that format.

import ./containers/[amiga_8svx, amiga_16sv, amiga_acbm, amiga_adf, amiga_anim,
  amiga_dms, amiga_iff, amiga_ilbm, amiga_workbench_icon, amos_bank,
  amos_bank_set, amos_program, amos_sprite_icon_bank, bmp, gif_container, pcx,
  png_container, qoi, wav, zip_archive, zx_spectrum_screen_dump,
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
    vhkQoi
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

  VextParsedContainer* = ref object of RootObj
    ## Type-erased parsed input with a checked handler-kind tag.
    kind*: VextHandlerKind

  VextParsedValue*[T] = ref object of VextParsedContainer
    value*: T

  VextParsedWorkbenchIcon* = object
    icon*: WorkbenchIcon
    glow*: WorkbenchGlowIcon

  VextParsedZxTap* = object
    screens*: seq[ZxSpectrumTapScreen]
    listings*: seq[ZxSpectrumTapBasic]

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
  VextFormatHandler(typeId: QoiTypeId, kind: vhkQoi),
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

proc parsedValue*[T](parsed: VextParsedContainer,
    expectedKind: VextHandlerKind): T =
  ## Retrieves a parsed value while checking both its tag and concrete type.
  if parsed.isNil or parsed.kind != expectedKind or
      not (parsed of VextParsedValue[T]):
    raise newException(Defect, "parsed container does not match its handler")
  VextParsedValue[T](parsed).value

proc parse*(handler: VextFormatHandler,
    data: openArray[byte]): VextParsedContainer =
  ## Structurally validates and retains one format-specific parsed value.
  template parsed(parsedInput: untyped): VextParsedContainer =
    block:
      let typedValue = parsedInput
      VextParsedValue[type(typedValue)](
        kind: handler.kind, value: typedValue)
  case handler.kind
  of vhkWorkbenchIcon:
    result = parsed(VextParsedWorkbenchIcon(icon: parseWorkbenchIcon(data),
      glow: parseGlowIcon(data)))
  of vhkAmigaAcbm: result = parsed(parseAmigaAcbm(data))
  of vhkAmiga8svx: result = parsed(parseAmiga8svx(data))
  of vhkAmiga16sv: result = parsed(parseAmiga16sv(data))
  of vhkAmigaAdf: result = parsed(parseAmigaAdf(data))
  of vhkAmigaDms: result = parsed(parseAmigaDms(data))
  of vhkAmigaAnim: result = parsed(parseAmigaAnim(data))
  of vhkAmigaIlbm: result = parsed(parseAmigaIlbm(data))
  of vhkAmigaIff: result = parsed(parseAmigaIff(data))
  of vhkBmp: result = parsed(parseBmp(data))
  of vhkDib: result = parsed(parseDib(data))
  of vhkPng: result = parsed(parsePng(data))
  of vhkQoi: result = parsed(parseQoi(data))
  of vhkGif: result = parsed(parseGif(data))
  of vhkPcx: result = parsed(parsePcx(data))
  of vhkWav: result = parsed(parseWav(data))
  of vhkZip: result = parsed(parseZipArchive(data))
  of vhkAmosProgram: result = parsed(parseAmosProgram(data))
  of vhkAmosBankSet: result = parsed(parseAmosBankSet(data))
  of vhkAmosBank: result = parsed(parseAmosBank(data))
  of vhkAmosSpriteBank, vhkAmosIconBank:
    let bank = parseAmosSpriteIconBank(data)
    if bank.amosSpriteIconBankTypeId != handler.typeId:
      raise newException(ValueError,
        "AMOS bank identifier does not match the selected format")
    result = parsed(bank)
  of vhkZxSpectrumScreen:
    if not isZxSpectrumScreenDump(data):
      raise newException(ValueError,
        "ZX Spectrum screen dump must contain exactly 6912 bytes")
    result = parsed(extractZxSpectrumScreenDump(data))
  of vhkZxSpectrumSnapshot:
    if not isZxSpectrumSnapshotSize(data.len):
      raise newException(ValueError,
        "ZX Spectrum snapshot must contain exactly 49179, 131103, or 147487 bytes")
    result = parsed(@data)
  of vhkZxSpectrumTap:
    if not isZxSpectrumTap(data):
      raise newException(ValueError, "invalid ZX Spectrum TAP container")
    result = parsed(VextParsedZxTap(screens: parseZxSpectrumTapScreens(data),
      listings: parseZxSpectrumTapBasic(data)))

proc tryParse*(handler: VextFormatHandler,
    data: openArray[byte]): VextParsedContainer =
  ## Returns nil when the bytes are not a valid instance of this format.
  try:
    result = handler.parse(data)
  except ValueError:
    discard
