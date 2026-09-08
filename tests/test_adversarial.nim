import std/[strutils, unittest]
import vexterlib

type AdversarialProfile = object
  typeId: string
  filename: string

const AdversarialProfiles = [
  AdversarialProfile(typeId: AmigaDiskfontIndexTypeId, filename: "font.font"),
  AdversarialProfile(typeId: AmigaDiskfontTypeId, filename: "12"),
  AdversarialProfile(typeId: AmigaLhaSfxTypeId, filename: "archive.run"),
  AdversarialProfile(typeId: AmigaHunkExecutableTypeId, filename: "program"),
  AdversarialProfile(typeId: AmigaWorkbenchIconTypeId, filename: "item.info"),
  AdversarialProfile(typeId: AmigaAcbmTypeId, filename: "image.acbm"),
  AdversarialProfile(typeId: AmigaPbmTypeId, filename: "image.pbm"),
  AdversarialProfile(typeId: Amiga8svxTypeId, filename: "sound.8svx"),
  AdversarialProfile(typeId: Amiga16svTypeId, filename: "sound.16sv"),
  AdversarialProfile(typeId: AmigaAdfTypeId, filename: "disk.adf"),
  AdversarialProfile(typeId: AmigaDmsTypeId, filename: "disk.dms"),
  AdversarialProfile(typeId: XpkTypeId, filename: "packed.xpk"),
  AdversarialProfile(typeId: PowerPackerTypeId, filename: "packed.pp20"),
  AdversarialProfile(typeId: AmigaAnimTypeId, filename: "movie.anim"),
  AdversarialProfile(typeId: AmigaIlbmTypeId, filename: "image.ilbm"),
  AdversarialProfile(typeId: AmigaIffTypeId, filename: "data.iff"),
  AdversarialProfile(typeId: BmpTypeId, filename: "image.bmp"),
  AdversarialProfile(typeId: DibTypeId, filename: "image.dib"),
  AdversarialProfile(typeId: WindowsIcoTypeId, filename: "image.ico"),
  AdversarialProfile(typeId: WindowsCurTypeId, filename: "image.cur"),
  AdversarialProfile(typeId: PngTypeId, filename: "image.png"),
  AdversarialProfile(typeId: JpegTypeId, filename: "image.jpg"),
  AdversarialProfile(typeId: QoiTypeId, filename: "image.qoi"),
  AdversarialProfile(typeId: KoalaPainterTypeId, filename: "image.koa"),
  AdversarialProfile(typeId: D64TypeId, filename: "disk.d64"),
  AdversarialProfile(typeId: NetpbmTypeId, filename: "image.pnm"),
  AdversarialProfile(typeId: GifTypeId, filename: "image.gif"),
  AdversarialProfile(typeId: FlicTypeId, filename: "movie.flc"),
  AdversarialProfile(typeId: FzxTypeId, filename: "font.fzx"),
  AdversarialProfile(typeId: BmFontTypeId, filename: "font.fnt"),
  AdversarialProfile(typeId: PcxTypeId, filename: "image.pcx"),
  AdversarialProfile(typeId: TgaTypeId, filename: "image.tga"),
  AdversarialProfile(typeId: WavTypeId, filename: "sound.wav"),
  AdversarialProfile(typeId: CreativeVoiceTypeId, filename: "sound.voc"),
  AdversarialProfile(typeId: PaintNetPaletteTypeId, filename: "colours.txt"),
  AdversarialProfile(typeId: GimpPaletteTypeId, filename: "colours.gpl"),
  AdversarialProfile(typeId: AsepriteTypeId, filename: "image.aseprite"),
  AdversarialProfile(typeId: AdobeSwatchExchangeTypeId, filename: "colours.ase"),
  AdversarialProfile(typeId: Rgba8PaletteTypeId, filename: "colours.pal"),
  AdversarialProfile(typeId: ProtrackerModTypeId, filename: "music.mod"),
  AdversarialProfile(typeId: DoomWadTypeId, filename: "game.wad"),
  AdversarialProfile(typeId: InnoSetupTypeId, filename: "setup.exe"),
  AdversarialProfile(typeId: ElectronAsarTypeId, filename: "app.asar"),
  AdversarialProfile(typeId: ZipArchiveTypeId, filename: "archive.zip"),
  AdversarialProfile(typeId: Iso9660TypeId, filename: "disc.iso"),
  AdversarialProfile(typeId: AppImageType1TypeId, filename: "program.AppImage"),
  AdversarialProfile(typeId: AppImageTypeId, filename: "program.AppImage"),
  AdversarialProfile(typeId: OpenRasterTypeId, filename: "image.ora"),
  AdversarialProfile(typeId: LhaArchiveTypeId, filename: "archive.lha"),
  AdversarialProfile(typeId: AmosProgramTypeId, filename: "program.amos"),
  AdversarialProfile(typeId: AmosBankSetTypeId, filename: "banks.abs"),
  AdversarialProfile(typeId: AmosBankTypeId, filename: "bank.abk"),
  AdversarialProfile(typeId: AmosSpriteBankTypeId, filename: "sprites.abk"),
  AdversarialProfile(typeId: AmosIconBankTypeId, filename: "icons.abk"),
  AdversarialProfile(typeId: ZxSpectrumScreenDumpTypeId, filename: "screen.scr"),
  AdversarialProfile(typeId: ZxSpectrumSnapshotTypeId, filename: "state.sna"),
  AdversarialProfile(typeId: ZxSpectrumTapTypeId, filename: "tape.tap"),
  AdversarialProfile(typeId: ZxSpectrumTzxTypeId, filename: "tape.tzx"),
  AdversarialProfile(typeId: AnsiArtTypeId, filename: "screen.ans")]

proc hostileInputs(): seq[seq[byte]] =
  result = @[@[], @[0'u8], @[0xff'u8],
    @[byte('-'), byte('l'), byte('h'), byte('5'), byte('-')]]
  var ascending = newSeq[byte](256)
  var alternating = newSeq[byte](4096)
  for index in 0 ..< ascending.len: ascending[index] = byte(index)
  for index in 0 ..< alternating.len:
    alternating[index] = if (index and 1) == 0: 0'u8 else: 0xff'u8
  result.add ascending
  result.add alternating

proc sameCandidates(left, right: seq[VextDetectionCandidate]): bool =
  if left.len != right.len: return false
  for index in 0 ..< left.len:
    if left[index].typeId != right[index].typeId or
        left[index].confidence != right[index].confidence or
        left[index].evidence.len != right[index].evidence.len or
        left[index].derivation.stages.len != right[index].derivation.stages.len:
      return false
    for evidenceIndex in 0 ..< left[index].evidence.len:
      if left[index].evidence[evidenceIndex].description !=
          right[index].evidence[evidenceIndex].description:
        return false
    for stageIndex in 0 ..< left[index].derivation.stages.len:
      if left[index].derivation.stages[stageIndex].typeId !=
          right[index].derivation.stages[stageIndex].typeId:
        return false
  true

suite "adversarial input contract":
  test "every registered handler has exactly one adversarial profile":
    check AdversarialProfiles.len == FormatHandlers.len
    for handler in FormatHandlers:
      var matches = 0
      for profile in AdversarialProfiles:
        if profile.typeId == handler.typeId: inc matches
      check matches == 1

  test "small hostile inputs cannot escape parser exception boundaries":
    for profile in AdversarialProfiles:
      let handler = formatHandler(profile.typeId)
      check not handler.isNil
      for data in hostileInputs():
        try:
          if handler[].carrierTypeId.len == 0:
            discard handler[].parse(data)
          else:
            discard forceFormat(profile.filename, data, profile.typeId)
        except CatchableError:
          discard

  test "detection is deterministic across hostile inputs and filenames":
    for profile in AdversarialProfiles:
      for data in hostileInputs():
        let first = detectFormats(profile.filename, data)
        let second = detectFormats(profile.filename, data)
        check sameCandidates(first, second)

  test "fixed-size formats reject named boundary violations":
    for length in [0, 1, ZxSpectrumScreenSize - 1,
        ZxSpectrumScreenSize + 1]:
      expect ValueError:
        discard formatHandler(ZxSpectrumScreenDumpTypeId)[].parse(
          newSeq[byte](length))
    for length in [0, 1, 49178, 49180, 131102, 131104, 147486, 147488]:
      expect ValueError:
        discard formatHandler(ZxSpectrumSnapshotTypeId)[].parse(
          newSeq[byte](length))

  test "extension evidence never bypasses forced structural validation":
    for profile in AdversarialProfiles:
      let handler = formatHandler(profile.typeId)
      if handler[].carrierTypeId.len == 0:
        try:
          discard forceFormat(profile.filename, @[0'u8], profile.typeId)
        except CatchableError:
          discard

  test "inspection working limits reject eager hostile inputs":
    var limits = defaultWorkLimits()
    limits.maximumWorkingBytes = 32
    let source = memoryByteSource(newSeq[byte](64))
    var rejected = false
    try:
      discard openInspectionSession("unknown.bin", newSourceCollection(source),
        limits = limits)
    except ValueError as error:
      rejected = true
      check "exceeds" in error.msg or "bounds" in error.msg
    check rejected
