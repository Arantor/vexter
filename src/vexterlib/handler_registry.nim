## Registry of input formats understood by the operations layer.
##
## Detection remains evidence-based and may return several candidates.  This
## registry is the authoritative bridge from a stable type identifier to the
## validation and inspection implementation for that format.

import ./containers/[amiga_8svx, amiga_16sv, amiga_acbm, amiga_adf, amiga_anim,
  amiga_diskfont, amiga_dms, amiga_hunk_executable, amiga_iff, amiga_ilbm, amiga_lha_sfx,
  amiga_workbench_icon, amos_bank,
  amos_bank_set, amos_program, amos_sprite_icon_bank, ansi_art, bmp, flic, gif_container,
  bmfont, fzx, jpeg, lha_archive, netpbm, openraster, pcx, png_container, powerpacker, qoi, tga, wav, windows_icon, zip_archive,
  zx_spectrum_screen_dump, zx_spectrum_snapshot, zx_spectrum_tap, xpk_shri]
import ./containers/amiga_pbm
import ./format_detection_types
type
  VextHandlerKind* = enum
    vhkWorkbenchIcon
    vhkAmigaDiskfontIndex
    vhkAmigaDiskfont
    vhkAmigaHunkExecutable
    vhkAmigaLhaSfx
    vhkAmigaAcbm
    vhkAmigaPbm
    vhkAmiga8svx
    vhkAmiga16sv
    vhkAmigaAdf
    vhkAmigaDms
    vhkXpk
    vhkPowerPacker
    vhkAmigaAnim
    vhkAmigaIlbm
    vhkAmigaIff
    vhkBmp
    vhkDib
    vhkWindowsIcon
    vhkPng
    vhkJpeg
    vhkQoi
    vhkNetpbm
    vhkGif
    vhkFlic
    vhkFzx
    vhkBmFont
    vhkPcx
    vhkTga
    vhkWav
    vhkZip
    vhkOpenRaster
    vhkLha
    vhkAmosProgram
    vhkAmosBankSet
    vhkAmosBank
    vhkAmosSpriteBank
    vhkAmosIconBank
    vhkZxSpectrumScreen
    vhkZxSpectrumSnapshot
    vhkZxSpectrumTap
    vhkAnsiArt

  VextFormatHandler* = object
    typeId*: string
    kind*: VextHandlerKind
    ## Empty for physical formats; semantic formats name the parsed carrier
    ## through which their registered refiner must be invoked.
    carrierTypeId*: string

  VextParsedContainer* = ref object of RootObj
    ## Type-erased parsed input with a checked handler-kind tag.
    kind*: VextHandlerKind

  VextParsedValue*[T] = ref object of VextParsedContainer
    value*: T

  VextRefinementMatch* = object
    confidence*: VextDetectionConfidence
    evidence*: seq[VextDetectionEvidence]
    parsed*: VextParsedContainer

  VextRefinementProbe* = proc(filename: string, data: openArray[byte],
    carrier: VextParsedContainer): VextRefinementMatch {.closure.}

  VextFormatRefiner* = object
    ## A semantic format probe that consumes an already parsed carrier.
    typeId*: string
    carrierTypeId*: string
    probe*: VextRefinementProbe

  VextParsedWorkbenchIcon* = object
    icon*: WorkbenchIcon
    glow*: WorkbenchGlowIcon

  VextParsedZxTap* = object
    screens*: seq[ZxSpectrumTapScreen]
    listings*: seq[ZxSpectrumTapBasic]

const FormatHandlers* = [
  VextFormatHandler(typeId: AmigaDiskfontIndexTypeId,
    kind: vhkAmigaDiskfontIndex),
  VextFormatHandler(typeId: AmigaDiskfontTypeId, kind: vhkAmigaDiskfont),
  VextFormatHandler(typeId: AmigaLhaSfxTypeId, kind: vhkAmigaLhaSfx),
  VextFormatHandler(typeId: AmigaHunkExecutableTypeId,
    kind: vhkAmigaHunkExecutable),
  VextFormatHandler(typeId: AmigaWorkbenchIconTypeId, kind: vhkWorkbenchIcon),
  VextFormatHandler(typeId: AmigaAcbmTypeId, kind: vhkAmigaAcbm),
  VextFormatHandler(typeId: AmigaPbmTypeId, kind: vhkAmigaPbm),
  VextFormatHandler(typeId: Amiga8svxTypeId, kind: vhkAmiga8svx),
  VextFormatHandler(typeId: Amiga16svTypeId, kind: vhkAmiga16sv),
  VextFormatHandler(typeId: AmigaAdfTypeId, kind: vhkAmigaAdf),
  VextFormatHandler(typeId: AmigaDmsTypeId, kind: vhkAmigaDms),
  VextFormatHandler(typeId: XpkTypeId, kind: vhkXpk),
  VextFormatHandler(typeId: PowerPackerTypeId, kind: vhkPowerPacker),
  VextFormatHandler(typeId: AmigaAnimTypeId, kind: vhkAmigaAnim),
  VextFormatHandler(typeId: AmigaIlbmTypeId, kind: vhkAmigaIlbm),
  VextFormatHandler(typeId: AmigaIffTypeId, kind: vhkAmigaIff),
  VextFormatHandler(typeId: BmpTypeId, kind: vhkBmp),
  VextFormatHandler(typeId: DibTypeId, kind: vhkDib),
  VextFormatHandler(typeId: WindowsIcoTypeId, kind: vhkWindowsIcon),
  VextFormatHandler(typeId: WindowsCurTypeId, kind: vhkWindowsIcon),
  VextFormatHandler(typeId: PngTypeId, kind: vhkPng),
  VextFormatHandler(typeId: JpegTypeId, kind: vhkJpeg),
  VextFormatHandler(typeId: QoiTypeId, kind: vhkQoi),
  VextFormatHandler(typeId: NetpbmTypeId, kind: vhkNetpbm),
  VextFormatHandler(typeId: GifTypeId, kind: vhkGif),
  VextFormatHandler(typeId: FlicTypeId, kind: vhkFlic),
  VextFormatHandler(typeId: FzxTypeId, kind: vhkFzx),
  VextFormatHandler(typeId: BmFontTypeId, kind: vhkBmFont),
  VextFormatHandler(typeId: PcxTypeId, kind: vhkPcx),
  VextFormatHandler(typeId: TgaTypeId, kind: vhkTga),
  VextFormatHandler(typeId: WavTypeId, kind: vhkWav),
  VextFormatHandler(typeId: ZipArchiveTypeId, kind: vhkZip),
  VextFormatHandler(typeId: OpenRasterTypeId, kind: vhkOpenRaster,
    carrierTypeId: ZipArchiveTypeId),
  VextFormatHandler(typeId: LhaArchiveTypeId, kind: vhkLha),
  VextFormatHandler(typeId: AmosProgramTypeId, kind: vhkAmosProgram),
  VextFormatHandler(typeId: AmosBankSetTypeId, kind: vhkAmosBankSet),
  VextFormatHandler(typeId: AmosBankTypeId, kind: vhkAmosBank),
  VextFormatHandler(typeId: AmosSpriteBankTypeId, kind: vhkAmosSpriteBank),
  VextFormatHandler(typeId: AmosIconBankTypeId, kind: vhkAmosIconBank),
  VextFormatHandler(typeId: ZxSpectrumScreenDumpTypeId,
    kind: vhkZxSpectrumScreen),
  VextFormatHandler(typeId: ZxSpectrumSnapshotTypeId,
    kind: vhkZxSpectrumSnapshot),
  VextFormatHandler(typeId: ZxSpectrumTapTypeId, kind: vhkZxSpectrumTap),
  VextFormatHandler(typeId: AnsiArtTypeId, kind: vhkAnsiArt)
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

proc formatRefiners*(): seq[VextFormatRefiner] =
  ## Authoritative semantic refiners. Format modules add entries here without
  ## teaching their physical carrier about package profiles.
  @[VextFormatRefiner(typeId: OpenRasterTypeId,
    carrierTypeId: ZipArchiveTypeId,
    probe: proc(filename: string, data: openArray[byte],
        carrier: VextParsedContainer): VextRefinementMatch =
      let archive = parsedValue[ZipArchive](carrier, vhkZip)
      if not archive.hasOpenRasterMimeMarker: return
      let document = parseOpenRaster(archive)
      result = VextRefinementMatch(confidence: vdcCertain,
        evidence: @[VextDetectionEvidence(description:
          "ZIP begins with the stored image/openraster MIME marker and " &
          "contains a valid baseline OpenRaster document")],
        parsed: VextParsedValue[OpenRasterDocument](kind: vhkOpenRaster,
          value: document))) ]

proc parse*(handler: VextFormatHandler,
    data: openArray[byte]): VextParsedContainer =
  ## Structurally validates and retains one format-specific parsed value.
  if handler.carrierTypeId.len > 0:
    raise newException(Defect,
      "semantic format handlers must be parsed through their carrier refiner")
  template parsed(parsedInput: untyped): VextParsedContainer =
    block:
      let typedValue = parsedInput
      VextParsedValue[type(typedValue)](
        kind: handler.kind, value: typedValue)
  case handler.kind
  of vhkAmigaDiskfontIndex: result = parsed(parseAmigaDiskfontIndex(data))
  of vhkAmigaDiskfont: result = parsed(parseAmigaDiskfont(data))
  of vhkAmigaLhaSfx: result = parsed(parseAmigaLhaSfx(data))
  of vhkAmigaHunkExecutable: result = parsed(parseAmigaHunkExecutable(data))
  of vhkWorkbenchIcon:
    result = parsed(VextParsedWorkbenchIcon(icon: parseWorkbenchIcon(data),
      glow: parseGlowIcon(data)))
  of vhkAmigaAcbm: result = parsed(parseAmigaAcbm(data))
  of vhkAmigaPbm: result = parsed(parseAmigaPbm(data))
  of vhkAmiga8svx: result = parsed(parseAmiga8svx(data))
  of vhkAmiga16sv: result = parsed(parseAmiga16sv(data))
  of vhkAmigaAdf: result = parsed(parseAmigaAdf(data))
  of vhkAmigaDms: result = parsed(parseAmigaDms(data))
  of vhkXpk: result = parsed(parseXpk(data))
  of vhkPowerPacker: result = parsed(parsePowerPacker(data))
  of vhkAmigaAnim: result = parsed(parseAmigaAnim(data))
  of vhkAmigaIlbm: result = parsed(parseAmigaIlbm(data))
  of vhkAmigaIff: result = parsed(parseAmigaIff(data))
  of vhkBmp: result = parsed(parseBmp(data))
  of vhkDib: result = parsed(parseDib(data))
  of vhkWindowsIcon:
    let icon = parseWindowsIcon(data)
    if icon.windowsIconTypeId != handler.typeId:
      raise newException(ValueError, "ICO/CUR type does not match the selected format")
    result = parsed(icon)
  of vhkPng: result = parsed(parsePng(data))
  of vhkJpeg: result = parsed(parseJpeg(data))
  of vhkQoi: result = parsed(parseQoi(data))
  of vhkNetpbm: result = parsed(parseNetpbm(data))
  of vhkGif: result = parsed(parseGif(data))
  of vhkFlic: result = parsed(parseFlic(data))
  of vhkFzx: result = parsed(parseFzx(data))
  of vhkBmFont: result = parsed(parseBmFont(data))
  of vhkPcx: result = parsed(parsePcx(data))
  of vhkTga: result = parsed(parseTga(data))
  of vhkWav: result = parsed(parseWav(data))
  of vhkZip: result = parsed(parseZipArchive(data))
  of vhkOpenRaster:
    raise newException(Defect,
      "OpenRaster must be parsed through its ZIP carrier refiner")
  of vhkLha: result = parsed(parseLhaArchive(data))
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
  of vhkAnsiArt: result = parsed(parseAnsiArt(data))

proc tryParse*(handler: VextFormatHandler,
    data: openArray[byte]): VextParsedContainer =
  ## Returns nil when the bytes are not a valid instance of this format.
  try:
    result = handler.parse(data)
  except ValueError:
    discard
