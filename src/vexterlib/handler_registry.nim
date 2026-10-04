## Registry of input formats understood by the operations layer.
##
## Detection remains evidence-based and may return several candidates.  This
## registry is the authoritative bridge from a stable type identifier to its
## support level and, when available, its validation and inspection parser.

import ./containers/[adobe_color_table, adobe_swatch_exchange, amiga_8svx, amiga_16sv, amiga_acbm, amiga_deep,
  amiga_adf, amiga_anim, amiga_dr2d, appimage, aseprite,
  amiga_diskfont, amiga_dms, amiga_hunk_executable, amiga_iff, amiga_ilbm,
  amiga_lha_sfx,
  amiga_workbench_icon, amos_bank,
  amos_bank_set, amos_program, amos_sprite_icon_bank, ansi_art, bmp, flic,
  gif_container,
  bmfont, creative_voice, d64, doom_wad, electron_asar, fat_disk_image, fzx, gimp_palette,
  inno_setup, iso9660, jasc_palette, jpeg, koala_painter, lha_archive, netpbm, openraster,
  paint_net_palette, pcx, pdf, png_container, powerpacker, protracker_mod, qoi,
  rgba8_palette, sqlite, tga, wav, windows_icon, windows_write, zip_archive,
  zx_spectrum_gigascreen_dump, zx_spectrum_next_image, zx_spectrum_next_palette,
  zx_spectrum_screen_dump, zx_spectrum_snapshot,
  zx_spectrum_tap,
  wordstar, zx_spectrum_tzx, xpk_shri]
import ./containers/amiga_pbm
import ./byte_sources
import ./format_detection_types
type
  VextHandlerKind* = enum
    vhkWorkbenchIcon
    vhkAmigaDiskfontIndex
    vhkAmigaDiskfont
    vhkAmigaHunkExecutable
    vhkAmigaLhaSfx
    vhkAmigaAcbm
    vhkAmigaDeep
    vhkAmigaPbm
    vhkAmiga8svx
    vhkAmiga16sv
    vhkAmigaAdf
    vhkAmigaDms
    vhkXpk
    vhkPowerPacker
    vhkAmigaAnim
    vhkAmigaDr2d
    vhkAmigaIlbm
    vhkAmigaIff
    vhkBmp
    vhkDib
    vhkWindowsIcon
    vhkPng
    vhkJpeg
    vhkQoi
    vhkKoalaPainter
    vhkD64
    vhkFatDiskImage
    vhkNetpbm
    vhkGif
    vhkFlic
    vhkFzx
    vhkBmFont
    vhkPcx
    vhkTga
    vhkWav
    vhkCreativeVoice
    vhkPaintNetPalette
    vhkGimpPalette
    vhkAseprite
    vhkAdobeSwatchExchange
    vhkAdobeColorTable
    vhkJascPalette
    vhkRgba8Palette
    vhkProtrackerMod
    vhkDoomWad
    vhkInnoSetup
    vhkElectronAsar
    vhkZip
    vhkIso9660
    vhkAppImageType1
    vhkAppImage
    vhkOpenRaster
    vhkLha
    vhkAmosProgram
    vhkAmosBankSet
    vhkAmosBank
    vhkAmosSpriteBank
    vhkAmosIconBank
    vhkZxSpectrumScreen
    vhkZxSpectrumGigascreen
    vhkZxSpectrumNextImage
    vhkZxSpectrumNextPalette
    vhkZxSpectrumSnapshot
    vhkZxSpectrumTap
    vhkZxSpectrumTzx
    vhkAnsiArt
    vhkWordStar
    vhkWindowsWrite
    vhkSqlite

  VextFormatHandler* = object
    typeId*: string
    kind*: VextHandlerKind
    support*: VextFormatSupport
    ## Empty for physical formats; semantic formats name the parsed carrier
    ## through which their registered refiner must be invoked.
    carrierTypeId*: string

  VextParsedContainer* = ref object of RootObj
    ## Type-erased parsed input with a checked handler-kind tag.
    kind*: VextHandlerKind

  VextParsedValue*[T] = ref object of VextParsedContainer
    value*: T

  VextRefinementMatch* = object
    ## `matched` distinguishes an intentional detection-only refinement from
    ## the default no-match value when no parsed representation is produced.
    matched*: bool
    confidence*: VextDetectionConfidence
    evidence*: seq[VextDetectionEvidence]
    parsed*: VextParsedContainer

  VextRefinementProbe* = proc(filename: string, data: openArray[byte],
    carrier: VextParsedContainer): VextRefinementMatch {.closure.}

  VextSourceRefinementProbe* = proc(filename: string,
    source: VextByteSource, carrier: VextParsedContainer):
    VextRefinementMatch {.closure.}

  VextFormatRefiner* = object
    ## A semantic format probe that consumes an already parsed carrier.
    typeId*: string
    carrierTypeId*: string
    probe*: VextRefinementProbe
    ## Optional random-access equivalent used by incremental sessions. A
    ## detection-only carrier profile should provide this whenever its evidence
    ## can be collected without materializing the complete carrier.
    sourceProbe*: VextSourceRefinementProbe

  VextParsedWorkbenchIcon* = object
    icon*: WorkbenchIcon
    glow*: WorkbenchGlowIcon

  VextParsedZxTap* = object
    records*: seq[ZxSpectrumTapRecord]

func detectionOnlyHandler*(typeId: string): VextFormatHandler =
  ## Declares a recognized physical format which deliberately has no parser.
  VextFormatHandler(typeId: typeId, support: vfsDetectionOnly)

const FormatHandlers* = [
  VextFormatHandler(typeId: AmigaDiskfontIndexTypeId,
    kind: vhkAmigaDiskfontIndex),
  VextFormatHandler(typeId: AmigaDiskfontTypeId, kind: vhkAmigaDiskfont),
  VextFormatHandler(typeId: AmigaLhaSfxTypeId, kind: vhkAmigaLhaSfx),
  VextFormatHandler(typeId: AmigaHunkExecutableTypeId,
    kind: vhkAmigaHunkExecutable),
  VextFormatHandler(typeId: AmigaWorkbenchIconTypeId, kind: vhkWorkbenchIcon),
  VextFormatHandler(typeId: AmigaAcbmTypeId, kind: vhkAmigaAcbm),
  VextFormatHandler(typeId: AmigaDeepTypeId, kind: vhkAmigaDeep),
  VextFormatHandler(typeId: AmigaPbmTypeId, kind: vhkAmigaPbm),
  VextFormatHandler(typeId: Amiga8svxTypeId, kind: vhkAmiga8svx),
  VextFormatHandler(typeId: Amiga16svTypeId, kind: vhkAmiga16sv),
  VextFormatHandler(typeId: AmigaAdfTypeId, kind: vhkAmigaAdf),
  VextFormatHandler(typeId: AmigaDmsTypeId, kind: vhkAmigaDms),
  VextFormatHandler(typeId: XpkTypeId, kind: vhkXpk),
  VextFormatHandler(typeId: PowerPackerTypeId, kind: vhkPowerPacker),
  VextFormatHandler(typeId: AmigaAnimTypeId, kind: vhkAmigaAnim),
  VextFormatHandler(typeId: AmigaDr2dTypeId, kind: vhkAmigaDr2d),
  VextFormatHandler(typeId: AmigaIlbmTypeId, kind: vhkAmigaIlbm),
  VextFormatHandler(typeId: AmigaIffTypeId, kind: vhkAmigaIff),
  VextFormatHandler(typeId: BmpTypeId, kind: vhkBmp),
  VextFormatHandler(typeId: DibTypeId, kind: vhkDib),
  VextFormatHandler(typeId: WindowsIcoTypeId, kind: vhkWindowsIcon),
  VextFormatHandler(typeId: WindowsCurTypeId, kind: vhkWindowsIcon),
  VextFormatHandler(typeId: PngTypeId, kind: vhkPng),
  VextFormatHandler(typeId: JpegTypeId, kind: vhkJpeg),
  VextFormatHandler(typeId: QoiTypeId, kind: vhkQoi),
  VextFormatHandler(typeId: KoalaPainterTypeId, kind: vhkKoalaPainter),
  VextFormatHandler(typeId: D64TypeId, kind: vhkD64),
  VextFormatHandler(typeId: FatDiskImageTypeId, kind: vhkFatDiskImage),
  VextFormatHandler(typeId: NetpbmTypeId, kind: vhkNetpbm),
  VextFormatHandler(typeId: GifTypeId, kind: vhkGif),
  VextFormatHandler(typeId: FlicTypeId, kind: vhkFlic),
  VextFormatHandler(typeId: FzxTypeId, kind: vhkFzx),
  VextFormatHandler(typeId: BmFontTypeId, kind: vhkBmFont),
  VextFormatHandler(typeId: PcxTypeId, kind: vhkPcx),
  VextFormatHandler(typeId: TgaTypeId, kind: vhkTga),
  VextFormatHandler(typeId: WavTypeId, kind: vhkWav),
  VextFormatHandler(typeId: CreativeVoiceTypeId, kind: vhkCreativeVoice),
  VextFormatHandler(typeId: PaintNetPaletteTypeId, kind: vhkPaintNetPalette),
  VextFormatHandler(typeId: GimpPaletteTypeId, kind: vhkGimpPalette),
  VextFormatHandler(typeId: AsepriteTypeId, kind: vhkAseprite),
  VextFormatHandler(typeId: AdobeSwatchExchangeTypeId,
    kind: vhkAdobeSwatchExchange),
  VextFormatHandler(typeId: AdobeColorTableTypeId,
    kind: vhkAdobeColorTable),
  VextFormatHandler(typeId: JascPaletteTypeId, kind: vhkJascPalette),
  VextFormatHandler(typeId: Rgba8PaletteTypeId, kind: vhkRgba8Palette),
  VextFormatHandler(typeId: ProtrackerModTypeId, kind: vhkProtrackerMod),
  VextFormatHandler(typeId: DoomWadTypeId, kind: vhkDoomWad),
  VextFormatHandler(typeId: InnoSetupTypeId, kind: vhkInnoSetup),
  VextFormatHandler(typeId: ElectronAsarTypeId, kind: vhkElectronAsar),
  VextFormatHandler(typeId: ZipArchiveTypeId, kind: vhkZip),
  VextFormatHandler(typeId: Iso9660TypeId, kind: vhkIso9660),
  VextFormatHandler(typeId: AppImageType1TypeId, kind: vhkAppImageType1),
  VextFormatHandler(typeId: AppImageTypeId, kind: vhkAppImage),
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
  VextFormatHandler(typeId: ZxSpectrumGigascreenTypeId,
    kind: vhkZxSpectrumGigascreen),
  VextFormatHandler(typeId: ZxSpectrumNextImageTypeId,
    kind: vhkZxSpectrumNextImage),
  VextFormatHandler(typeId: ZxSpectrumNextPaletteTypeId,
    kind: vhkZxSpectrumNextPalette),
  VextFormatHandler(typeId: ZxSpectrumSnapshotTypeId,
    kind: vhkZxSpectrumSnapshot),
  VextFormatHandler(typeId: ZxSpectrumTapTypeId, kind: vhkZxSpectrumTap),
  VextFormatHandler(typeId: ZxSpectrumTzxTypeId, kind: vhkZxSpectrumTzx),
  VextFormatHandler(typeId: AnsiArtTypeId, kind: vhkAnsiArt),
  VextFormatHandler(typeId: WordStarTypeId, kind: vhkWordStar),
  VextFormatHandler(typeId: WindowsWriteTypeId, kind: vhkWindowsWrite),
  detectionOnlyHandler(PdfTypeId),
  VextFormatHandler(typeId: SqliteTypeId, kind: vhkSqlite)
]

proc formatHandler*(typeId: string): ptr VextFormatHandler =
  ## Returns the registered handler for `typeId`, or nil when unsupported.
  for index in 0 .. FormatHandlers.high:
    if FormatHandlers[index].typeId == typeId:
      return unsafeAddr FormatHandlers[index]

func isInspectable*(handler: VextFormatHandler): bool =
  handler.support == vfsInspectable

proc parsedValue*[T](parsed: VextParsedContainer,
    expectedKind: VextHandlerKind): T =
  ## Retrieves a parsed value while checking both its tag and concrete type.
  if parsed.isNil or parsed.kind != expectedKind or
      not (parsed of VextParsedValue[T]):
    raise newException(Defect, "parsed container does not match its handler")
  VextParsedValue[T](parsed).value

proc parsedValueRef*[T](parsed: VextParsedContainer,
    expectedKind: VextHandlerKind): ptr T =
  ## Provides mutable access for large parsed containers whose owned payloads
  ## must be moved into the final resource tree without deep sequence copies.
  if parsed.isNil or parsed.kind != expectedKind or
      not (parsed of VextParsedValue[T]):
    raise newException(Defect, "parsed container does not match its handler")
  addr VextParsedValue[T](parsed).value

proc formatRefiners*(): seq[VextFormatRefiner] =
  ## Authoritative semantic refiners. Format modules add entries here without
  ## teaching their physical carrier about package profiles.
  @[VextFormatRefiner(typeId: OpenRasterTypeId,
    carrierTypeId: ZipArchiveTypeId,
    probe: proc(filename: string, data: openArray[byte],
        carrier: VextParsedContainer): VextRefinementMatch =
    let archive = parsedValue[ZipArchive](carrier, vhkZip)
    if not archive.hasOpenRasterMimeMarker(data): return
    let document = parseOpenRaster(archive, data)
    result = VextRefinementMatch(confidence: vdcCertain,
      matched: true,
      evidence: @[VextDetectionEvidence(description:
      "ZIP begins with the stored image/openraster MIME marker and " &
      "contains a valid baseline OpenRaster document")],
      parsed: VextParsedValue[OpenRasterDocument](kind: vhkOpenRaster,
        value: document)))]

proc parse*(handler: VextFormatHandler,
    data: openArray[byte]): VextParsedContainer =
  ## Structurally validates and retains one format-specific parsed value.
  if not handler.isInspectable:
    raise newException(ValueError,
      "format is recognized for detection only: " & handler.typeId)
  if handler.carrierTypeId.len > 0:
    raise newException(Defect,
      "semantic format handlers must be parsed through their carrier refiner")
  template parsed(parsedInput: untyped): VextParsedContainer =
    block:
      var typedValue = parsedInput
      VextParsedValue[type(typedValue)](
        kind: handler.kind, value: move(typedValue))
  case handler.kind
  of vhkAmigaDiskfontIndex: result = parsed(parseAmigaDiskfontIndex(data))
  of vhkAmigaDiskfont: result = parsed(parseAmigaDiskfont(data))
  of vhkAmigaLhaSfx: result = parsed(parseAmigaLhaSfx(data))
  of vhkAmigaHunkExecutable: result = parsed(parseAmigaHunkExecutable(data))
  of vhkWorkbenchIcon:
    result = parsed(VextParsedWorkbenchIcon(icon: parseWorkbenchIcon(data),
      glow: parseGlowIcon(data)))
  of vhkAmigaAcbm: result = parsed(parseAmigaAcbm(data))
  of vhkAmigaDeep: result = parsed(parseAmigaDeep(data))
  of vhkAmigaPbm: result = parsed(parseAmigaPbm(data))
  of vhkAmiga8svx: result = parsed(parseAmiga8svx(data))
  of vhkAmiga16sv: result = parsed(parseAmiga16sv(data))
  of vhkAmigaAdf: result = parsed(parseAmigaAdf(data))
  of vhkAmigaDms: result = parsed(parseAmigaDms(data))
  of vhkXpk: result = parsed(parseXpk(data))
  of vhkPowerPacker: result = parsed(parsePowerPacker(data))
  of vhkAmigaAnim: result = parsed(parseAmigaAnim(data))
  of vhkAmigaDr2d: result = parsed(parseAmigaDr2d(data))
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
  of vhkKoalaPainter: result = parsed(parseKoalaPainter(data))
  of vhkD64: result = parsed(parseD64(data))
  of vhkFatDiskImage: result = parsed(parseFatDiskImage(data))
  of vhkNetpbm: result = parsed(parseNetpbm(data))
  of vhkGif: result = parsed(parseGif(data))
  of vhkFlic: result = parsed(parseFlic(data))
  of vhkFzx: result = parsed(parseFzx(data))
  of vhkBmFont: result = parsed(parseBmFont(data))
  of vhkPcx: result = parsed(parsePcx(data))
  of vhkTga: result = parsed(parseTga(data))
  of vhkWav: result = parsed(parseWav(data))
  of vhkCreativeVoice: result = parsed(parseCreativeVoice(data))
  of vhkPaintNetPalette: result = parsed(parsePaintNetPalette(data))
  of vhkGimpPalette: result = parsed(parseGimpPalette(data))
  of vhkAseprite: result = parsed(parseAseprite(data))
  of vhkAdobeSwatchExchange:
    result = parsed(parseAdobeSwatchExchange(data))
  of vhkAdobeColorTable: result = parsed(parseAdobeColorTable(data))
  of vhkJascPalette: result = parsed(parseJascPalette(data))
  of vhkRgba8Palette: result = parsed(parseRgba8Palette(data))
  of vhkProtrackerMod: result = parsed(parseProtrackerMod(data))
  of vhkDoomWad: result = parsed(parseDoomWad(data))
  of vhkInnoSetup: result = parsed(parseInnoSetup(data))
  of vhkElectronAsar: result = parsed(parseElectronAsar(data))
  of vhkZip: result = parsed(parseZipArchive(data))
  of vhkIso9660: result = parsed(parseIso9660(data))
  of vhkAppImageType1: result = parsed(parseAppImageType1(data))
  of vhkAppImage: result = parsed(parseAppImage(data))
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
        "ZX Spectrum screen dump must contain 6912 raw bytes or a valid 7040-byte +3DOS screen")
    result = parsed(extractZxSpectrumScreenDump(data))
  of vhkZxSpectrumGigascreen:
    result = parsed(parseZxSpectrumGigascreen(data))
  of vhkZxSpectrumNextImage:
    result = parsed(parseZxSpectrumNextImage(data))
  of vhkZxSpectrumNextPalette:
    result = parsed(parseZxSpectrumNextPalette(data))
  of vhkZxSpectrumSnapshot:
    if not isZxSpectrumSnapshotSize(data.len):
      raise newException(ValueError,
        "ZX Spectrum snapshot must contain exactly 49179, 131103, or 147487 bytes")
    result = parsed(@data)
  of vhkZxSpectrumTap:
    if not isZxSpectrumTap(data):
      raise newException(ValueError, "invalid ZX Spectrum TAP container")
    result = parsed(VextParsedZxTap(records: parseZxSpectrumTapRecords(data)))
  of vhkZxSpectrumTzx:
    result = parsed(VextParsedZxTap(records: parseZxSpectrumTzx(data).records))
  of vhkAnsiArt: result = parsed(parseAnsiArt(data))
  of vhkWordStar: result = parsed(parseWordStar(data))
  of vhkWindowsWrite: result = parsed(parseWindowsWrite(data))
  of vhkSqlite: result = parsed(parseSqlite(data))

proc tryParse*(handler: VextFormatHandler,
    data: openArray[byte]): VextParsedContainer =
  ## Returns nil when the bytes are not a valid instance of this format.
  try:
    result = handler.parse(data)
  except ValueError:
    discard
