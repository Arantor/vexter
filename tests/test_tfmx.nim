import std/[unittest, sequtils]
import vexterlib

proc putWord(data: var seq[byte], offset, value: int) =
  data[offset] = byte((value shr 8) and 255)
  data[offset+1] = byte(value and 255)
proc putLong(data: var seq[byte], offset, value: int) =
  data.putWord(offset,value shr 16)
  data.putWord(offset+2,value and 65535)
proc instruction(data: var seq[byte], offset: int, bytes: array[4,int]) =
  for i in 0 ..< 4: data[offset+i] = byte(bytes[i])
proc fixture(packed = false): seq[byte] =
  result = newSeq[byte](0xb00)
  for i,c in "TFMX-SONG ": result[i] = byte(c)
  if packed:
    result.putLong(0x1d0,0x800)
    result.putLong(0x1d4,0x400)
    result.putLong(0x1d8,0x600)
  result.putLong(0x400,0x900)
  result.putLong(0x600,0xa00)
  for i in 1 ..< 8: result.putWord(0x800+i*2,0xff00)
  result.instruction(0x900,[0x9e,0,0xf0,4]) # C3, macro 0, channel 0, wait.
  result.instruction(0x904,[0xf0,0,0,0])
  result.instruction(0xa00,[0x00,0,0,0])
  result.instruction(0xa04,[0x02,0,0,4])
  result.instruction(0xa08,[0x03,0,0,2])
  result.instruction(0xa0c,[0x08,0,0,0])
  result.instruction(0xa10,[0x01,0,0,0])
  result.instruction(0xa14,[0x07,0,0,0])
const Samples = [0'u8,0,0,0,127,0,128,0]

proc effectFixture(effect: array[4,int], target = 680, dmaFlag = 0): seq[byte] =
  result = fixture()
  result.instruction(0x900,[0x9e,0,0xf0,255])
  result.instruction(0xa0c,[0x17,0,2,168]) # Absolute period 680.
  result.instruction(0xa10,[0x01,dmaFlag,0,0])
  result.instruction(0xa14,effect)
  result.instruction(0xa18,[0x17,0,target shr 8,target and 255])
  result.instruction(0xa1c,[0x07,0,0,0])

const SquareSamples = [0'u8,0,0,0,127,127,129,129]

proc risingCrossings(sound: VextSound, first, last: int): seq[int] =
  let samples = sound.buffer.channels[0]
  for i in max(first,1) ..< min(last,samples.len):
    if samples[i] > 0 and samples[i-1] <= 0: result.add i

proc crossingGaps(sound: VextSound): seq[int] =
  let crossings = sound.risingCrossings(4410,19845)
  for i in 1 ..< crossings.len: result.add crossings[i]-crossings[i-1]

suite "TFMX":
  test "magic and validated unpacked/packed sections identify music":
    for packed in [false,true]:
      let data = fixture(packed)
      let music = parseTfmx(data)
      check music.trackOffset == 0x800
      check music.patternOffset == 0x400
      check music.macroOffset == 0x600
      check music.songs.len == 1
      check music.pointer(false,0) == 0x900
      check detectFormats("no-extension",data)[0].typeId == TfmxTypeId
    check not isTfmx(newSeq[byte](512))
    var broken = fixture()
    broken.putLong(0x1d0,0x7fffffff)
    expect ValueError: discard parseTfmx(broken)
    broken = fixture()
    broken.putWord(0x140,65535)
    expect ValueError: discard parseTfmx(broken)

  test "macro precedes pattern clock; signed PCM and stereo routing are deterministic":
    let music = parseTfmx(fixture())
    let first = renderTfmx(music,Samples,maximumSeconds=1,applyFilter=false)
    let second = renderTfmx(music,Samples,maximumSeconds=1,applyFilter=false)
    check first.termination == "song end"
    check first.sound.sampleRate == 22050
    check first.sound.buffer.channels == second.sound.buffer.channels
    check first.sound.buffer.sampleCount == 2646
    check first.sound.buffer.channels[0][0 ..< 441].allIt(it == 0)
    check first.sound.buffer.channels[0][441] == 11430
    check first.sound.buffer.channels[0].anyIt(it > 0)
    check first.sound.buffer.channels[0].anyIt(it < 0)
    check first.sound.buffer.channels[1].allIt(it == 0)

  test "pattern tempo division does not slow the macro clock":
    var data = fixture()
    data.putWord(0x180,3)
    let audio = renderTfmx(parseTfmx(data),Samples,maximumSeconds=1,applyFilter=false).sound
    check audio.buffer.sampleCount == 9261
    check audio.buffer.channels[0][441] == 11430

  test "sample registers reload at a boundary instead of replacing active DMA":
    var data = fixture()
    # Start four bytes, then install silent repeat registers on the next tick.
    data.instruction(0xa14,[0x04,0,0,0])
    data.instruction(0xa18,[0x19,0,0,0])
    data.instruction(0xa1c,[0x07,0,0,0])
    let audio = renderTfmx(parseTfmx(data),Samples,maximumSeconds=1).sound
    check audio.buffer.channels[0][441 ..< 882].anyIt(it != 0)
    check audio.buffer.channels[0][1000 .. ^1].allIt(it == 0)

  test "companions remain optional for structural inspection and required for audio":
    let missing = inspectSource("mdat.test",fixture())
    check missing.warnings.len == 1
    expect ValueError: discard renderTfmx(parseTfmx(fixture()),@[],maximumSeconds=1)
    var requested: string
    let loaded = inspectSource("mdat.test",fixture(),companionResolver =
      proc(name: string): seq[byte] =
        requested = name
        @Samples)
    check requested == "smpl.test"
    check loaded.warnings.len == 0
    let audio = loaded.resources.roots[0].children[^1].children[0]
    check audio.kind == vrnkAudio
    check audio.audioSound.buffer.channels[0].anyIt(it != 0)
    let exported = exportResource(loaded.resources,VextExportRequest(
      resourcePath: "/module/songs/0/rendered-audio", outputFormat: "wav"))
    check exported.artifacts.artifacts.len == 1

  test "deferred subsong sounds retain their own source song index":
    var data = fixture()
    data.putWord(0x102,1)
    data.putWord(0x142,1)
    data.putLong(0x404,0x920)
    data.putWord(0x810,0x0100)
    for i in 1 ..< 8: data.putWord(0x810+i*2,0xff00)
    data.instruction(0x920,[0x9e,0,0xf1,2])
    data.instruction(0x924,[0xf0,0,0,0])
    let loaded = inspectSource("mdat.test",data,companionResolver =
      proc(name: string): seq[byte] = @Samples)
    var previews: seq[VextResourceNode]
    for resource in loaded.resources.leafResources:
      if resource.kind == vrnkAudio: previews.add resource
    check previews.len == 2
    let first = previews[0].audioSound
    let second = previews[1].audioSound
    check first.buffer.channels[0].anyIt(it != 0)
    check first.buffer.channels[1].allIt(it == 0)
    check second.buffer.channels[0].allIt(it == 0)
    check second.buffer.channels[1].anyIt(it != 0)
    check first.buffer.sampleCount > second.buffer.sampleCount

  test "classic portamento uses period steps rather than Professional multiplication":
    let music = parseTfmx(effectFixture([0x0b,1,0,4],270))
    let classic = renderTfmx(music,SquareSamples,maximumSeconds=1,applyFilter=false).sound
    let professional = renderTfmx(music,SquareSamples,maximumSeconds=1,
      effectMode=temProfessional,applyFilter=false).sound
    # Four-byte square wave: periods 584..548 during this interval yield
    # approximately 312 cycles. A proportional sweep is substantially faster.
    check classic.risingCrossings(11025,15435).len in 305 .. 320
    check professional.risingCrossings(11025,15435).len in 405 .. 435

  test "classic detuning adds period units while Professional detuning scales them":
    var data = fixture()
    data.instruction(0x900,[0x9e,0,0xf0,255])
    data.instruction(0xa0c,[0x08,0,0,128])
    let music = parseTfmx(data)
    let classic = renderTfmx(music,SquareSamples,maximumSeconds=1,applyFilter=false).sound
    let professional = renderTfmx(music,SquareSamples,maximumSeconds=1,
      effectMode=temProfessional,applyFilter=false).sound
    # Note 30 has period 303: classic +128 -> 431; Professional *1.5 -> 454.
    check classic.risingCrossings(11025,15435).len in 410 .. 413
    check professional.risingCrossings(11025,15435).len in 389 .. 392

  test "classic vibrato adds period units and DMA flags control effect startup":
    let music = parseTfmx(effectFixture([0x0c,4,0,40]))
    let classic = renderTfmx(music,SquareSamples,maximumSeconds=1,applyFilter=false).sound
    let professional = renderTfmx(music,SquareSamples,maximumSeconds=1,
      effectMode=temProfessional,applyFilter=false).sound
    let held = renderTfmx(parseTfmx(effectFixture([0x0c,4,0,40],dmaFlag=255)),
      SquareSamples,maximumSeconds=1,applyFilter=false).sound
    # Classic triangle: period 680 +/- 80; Professional: roughly +/- 4%.
    check classic.crossingGaps.min <= 15
    check classic.crossingGaps.max >= 19
    check professional.crossingGaps.min >= 16
    check professional.crossingGaps.max <= 18
    check held.crossingGaps.max-held.crossingGaps.min <= 1

  test "fixed output filtering attenuates treble and preserves silence in the other lane":
    let music = parseTfmx(effectFixture([0x17,0,0,113],113))
    let raw = renderTfmx(music,SquareSamples,maximumSeconds=1,applyFilter=false).sound
    let filtered = renderTfmx(music,SquareSamples,maximumSeconds=1).sound
    var rawEnergy, filteredEnergy: int64
    for i in 4410 ..< 19845:
      rawEnergy += int64(raw.buffer.channels[0][i])*raw.buffer.channels[0][i]
      filteredEnergy += int64(filtered.buffer.channels[0][i])*filtered.buffer.channels[0][i]
    check filteredEnergy < rawEnergy div 2
    check filtered.buffer.channels[1].allIt(it == 0)

  test "invalid jumps, unsupported synthesis and runaway programs fail within bounds":
    var data = fixture()
    data.instruction(0x900,[0xf2,0,0xff,0xff])
    expect ValueError: discard renderTfmx(parseTfmx(data),Samples,maximumSeconds=1)
    data = fixture()
    data.instruction(0x900,[0xf1,0,0,0])
    expect ValueError: discard renderTfmx(parseTfmx(data),Samples,maximumSeconds=1)
    data = fixture()
    data.instruction(0xa00,[0x22,0,0,0])
    expect ValueError: discard renderTfmx(parseTfmx(data),Samples,maximumSeconds=1)
    data = fixture()
    data.instruction(0x900,[0x9e,0,0xf4,4])
    expect ValueError: discard renderTfmx(parseTfmx(data),Samples,maximumSeconds=1)

  test "infinite musical loops produce duration-limited previews":
    var data = fixture()
    data.instruction(0x904,[0xf1,0,0,0])
    let audio = renderTfmx(parseTfmx(data),Samples,maximumSeconds=1)
    check audio.termination == "preview duration limit"
    check audio.sound.buffer.sampleCount == 22050
