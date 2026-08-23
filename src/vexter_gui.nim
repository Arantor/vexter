## Native dependency-free Windows viewer for vexterlib.

when not defined(windows):
  {.error: "vexter_gui is available only when targeting Windows".}

import std/[math, os, strformat, strutils, widestrs]
import vexterlib

{.passC: "-D_WIN32_WINNT=0x0601 -DWINVER=0x0601 -include windows.h".}
{.passL: "-lcomctl32 -lcomdlg32 -lgdi32 -lwinmm".}
{.emit: """
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <commdlg.h>
""".}

type
  HWND = pointer
  HINSTANCE = pointer
  HMENU = pointer
  HDC = pointer
  HBRUSH = pointer
  HICON = pointer
  HIMAGELIST = pointer
  HTREEITEM = pointer
  HWAVEOUT = pointer
  UINT = uint32
  DWORD = uint32
  WPARAM = uint
  LPARAM = int
  LRESULT = int
  BOOL = int32
  WORD = uint16

  RECT {.importc: "RECT", header: "<windows.h>".} = object
    left, top, right, bottom: int32
  PAINTSTRUCT {.importc: "PAINTSTRUCT", header: "<windows.h>".} = object
    hdc: HDC
    fErase: BOOL
    rcPaint: RECT
    fRestore, fIncUpdate: BOOL
    rgbReserved: array[32, byte]
  WNDCLASSEXW {.importc: "WNDCLASSEXW", header: "<windows.h>".} = object
    cbSize, style: UINT
    lpfnWndProc: pointer
    cbClsExtra, cbWndExtra: int32
    hInstance: HINSTANCE
    hIcon, hCursor: pointer
    hbrBackground: HBRUSH
    lpszMenuName, lpszClassName: WideCString
    hIconSm: pointer
  MSG {.importc: "MSG", header: "<windows.h>".} = object
    hwnd: HWND
    message: UINT
    wParam: WPARAM
    lParam: LPARAM
    time: DWORD
    ptX, ptY: int32
  OPENFILENAMEW {.importc: "OPENFILENAMEW", header: "<commdlg.h>".} = object
    lStructSize: DWORD
    hwndOwner: HWND
    hInstance: HINSTANCE
    lpstrFilter, lpstrCustomFilter: WideCString
    nMaxCustFilter, nFilterIndex: DWORD
    lpstrFile: WideCString
    nMaxFile: DWORD
    lpstrFileTitle: WideCString
    nMaxFileTitle: DWORD
    lpstrInitialDir, lpstrTitle: WideCString
    Flags: DWORD
    nFileOffset, nFileExtension: WORD
    lpstrDefExt: WideCString
    lCustData: LPARAM
    lpfnHook, lpTemplateName, pvReserved: pointer
    dwReserved, FlagsEx: DWORD
  TVITEMW {.importc: "TVITEMW", header: "<commctrl.h>".} = object
    mask: UINT
    hItem: HTREEITEM
    state, stateMask: UINT
    pszText: WideCString
    cchTextMax, iImage, iSelectedImage, cChildren: int32
    lParam: LPARAM
  TVINSERTSTRUCTW {.importc: "TVINSERTSTRUCTW", header: "<commctrl.h>".} = object
    hParent, hInsertAfter: HTREEITEM
    item: TVITEMW
  NMHDR {.importc: "NMHDR", header: "<commctrl.h>".} = object
    hwndFrom: HWND
    idFrom: uint
    code: UINT
  NMTREEVIEWW {.importc: "NMTREEVIEWW", header: "<commctrl.h>".} = object
    hdr: NMHDR
    action: UINT
    itemOld, itemNew: TVITEMW
    ptDragX, ptDragY: int32
  BITMAPINFOHEADER {.importc: "BITMAPINFOHEADER", header: "<windows.h>".} = object
    biSize: DWORD
    biWidth, biHeight: int32
    biPlanes, biBitCount: WORD
    biCompression, biSizeImage: DWORD
    biXPelsPerMeter, biYPelsPerMeter: int32
    biClrUsed, biClrImportant: DWORD
  BITMAPINFO {.importc: "BITMAPINFO", header: "<windows.h>".} = object
    bmiHeader: BITMAPINFOHEADER
    bmiColors: array[1, uint32]
  WAVEFORMATEX = object
    wFormatTag, nChannels: WORD
    nSamplesPerSec, nAvgBytesPerSec: DWORD
    nBlockAlign, wBitsPerSample, cbSize: WORD
  WAVEHDR = object
    lpData: cstring
    dwBufferLength, dwBytesRecorded: DWORD
    dwUser: uint
    dwFlags, dwLoops: DWORD
    lpNext: pointer
    reserved: uint

  ViewKind = enum vkNone, vkRaster, vkFont, vkAudio, vkText
  TreeBinding = ref object
    node: VextResourceNode
    metadataText: string
  LoadResult = object
    inspection: VextInspection
    filename: string
    error: string
  LoadJob = tuple[filename: string, result: ptr LoadResult]

const
  WS_OVERLAPPEDWINDOW = 0x00CF0000'u32
  WS_CHILD = 0x40000000'u32
  WS_VISIBLE = 0x10000000'u32
  WS_CLIPCHILDREN = 0x02000000'u32
  WS_BORDER = 0x00800000'u32
  WS_VSCROLL = 0x00200000'u32
  ES_MULTILINE = 0x0004'u32
  ES_AUTOVSCROLL = 0x0040'u32
  ES_READONLY = 0x0800'u32
  ES_AUTOHSCROLL = 0x0080'u32
  CBS_DROPDOWNLIST = 0x0003'u32
  TVS_HASBUTTONS = 0x0001'u32
  TVS_HASLINES = 0x0002'u32
  TVS_LINESATROOT = 0x0004'u32
  PBST_MARQUEE = 0x0008'u32
  CW_USEDEFAULT = low(int32)
  SW_SHOW = 5
  WM_CREATE = 0x0001'u32
  WM_DESTROY = 0x0002'u32
  WM_SIZE = 0x0005'u32
  WM_PAINT = 0x000F'u32
  WM_CLOSE = 0x0010'u32
  WM_COMMAND = 0x0111'u32
  WM_TIMER = 0x0113'u32
  WM_NOTIFY = 0x004E'u32
  WM_APP = 0x8000'u32
  WM_LOAD_DONE = WM_APP + 1
  CB_ADDSTRING = 0x0143'u32
  CB_RESETCONTENT = 0x014B'u32
  CB_SETCURSEL = 0x014E'u32
  CB_GETCURSEL = 0x0147'u32
  PBM_SETMARQUEE = WM_APP + 10
  TVM_INSERTITEMW = 0x1132'u32
  TVM_DELETEITEM = 0x1101'u32
  TVM_EXPAND = 0x1102'u32
  TVM_SELECTITEM = 0x110B'u32
  TVM_SETIMAGELIST = 0x1109'u32
  TVE_EXPAND = 0x0002
  TVGN_CARET = 0x0009
  TVIF_TEXT = 0x0001'u32
  TVIF_IMAGE = 0x0002'u32
  TVIF_PARAM = 0x0004'u32
  TVIF_SELECTEDIMAGE = 0x0020'u32
  TVSIL_NORMAL = 0
  I_IMAGENONE = -2
  ILC_MASK = 0x0001'u32
  ILC_COLOR32 = 0x0020'u32
  TVI_ROOT = cast[HTREEITEM](-0x10000)
  TVI_LAST = cast[HTREEITEM](-0x0FFFE)
  TVN_SELCHANGEDW = cast[UINT](-451'i32)
  OFN_OVERWRITEPROMPT = 0x00000002'u32
  OFN_FILEMUSTEXIST = 0x00001000'u32
  OFN_PATHMUSTEXIST = 0x00000800'u32
  OFN_EXPLORER = 0x00080000'u32
  COLOR_WINDOW = 5
  COLOR_BTNFACE = 15
  IDC_ARROW = 32512
  IDI_WARNING = 32515
  DIB_RGB_COLORS = 0'u32
  SRCCOPY = 0x00CC0020'u32
  COLORONCOLOR = 3
  CS_VREDRAW = 0x0001'u32
  CS_HREDRAW = 0x0002'u32
  WAVE_FORMAT_PCM = 1'u16
  WAVE_MAPPER = cast[uint](-1)

proc RegisterClassExW(w: ptr WNDCLASSEXW): WORD {.stdcall, importc, header: "<windows.h>".}
proc CreateWindowExW(exStyle: DWORD, className, title: WideCString,
    style: DWORD, x, y, width, height: int32, parent: HWND, menu: HMENU,
    instance: HINSTANCE, param: pointer): HWND {.stdcall, importc, header: "<windows.h>".}
proc DefWindowProcW(hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall, importc, header: "<windows.h>".}
proc ShowWindow(hwnd: HWND, cmd: int32): BOOL {.stdcall, importc, header: "<windows.h>".}
proc UpdateWindow(hwnd: HWND): BOOL {.stdcall, importc, header: "<windows.h>".}
proc GetMessageW(msg: ptr MSG, hwnd: HWND, lo, hi: UINT): BOOL {.stdcall, importc, header: "<windows.h>".}
proc TranslateMessage(msg: ptr MSG): BOOL {.stdcall, importc, header: "<windows.h>".}
proc DispatchMessageW(msg: ptr MSG): LRESULT {.stdcall, importc, header: "<windows.h>".}
proc PostQuitMessage(code: int32) {.stdcall, importc, header: "<windows.h>".}
proc PostMessageW(hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM): BOOL {.stdcall, importc, header: "<windows.h>".}
proc SendMessageW(hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall, importc, header: "<windows.h>".}
proc MoveWindow(hwnd: HWND, x, y, width, height: int32, repaint: BOOL): BOOL {.stdcall, importc, header: "<windows.h>".}
proc GetClientRect(hwnd: HWND, rect: ptr RECT): BOOL {.stdcall, importc, header: "<windows.h>".}
proc GetLastError(): DWORD {.stdcall, importc, header: "<windows.h>".}
proc EnableWindow(hwnd: HWND, enabled: BOOL): BOOL {.stdcall, importc, header: "<windows.h>".}
proc SetWindowTextW(hwnd: HWND, text: WideCString): BOOL {.stdcall, importc, header: "<windows.h>".}
proc GetWindowTextLengthW(hwnd: HWND): int32 {.stdcall, importc, header: "<windows.h>".}
proc GetWindowTextW(hwnd: HWND, text: WideCString, maximum: int32): int32 {.stdcall, importc, header: "<windows.h>".}
proc BeginPaint(hwnd: HWND, ps: ptr PAINTSTRUCT): HDC {.stdcall, importc, header: "<windows.h>".}
proc EndPaint(hwnd: HWND, ps: ptr PAINTSTRUCT): BOOL {.stdcall, importc, header: "<windows.h>".}
proc FillRect(dc: HDC, rect: ptr RECT, brush: HBRUSH): int32 {.stdcall, importc, header: "<windows.h>".}
proc GetSysColorBrush(index: int32): HBRUSH {.stdcall, importc, header: "<windows.h>".}
proc LoadCursorW(instance: HINSTANCE, name: int): pointer {.stdcall, importc, header: "<windows.h>".}
proc LoadIconW(instance: HINSTANCE, name: int): HICON {.stdcall, importc, header: "<windows.h>".}
proc ImageList_Create(width, height: int32, flags: UINT, initial,
    grow: int32): HIMAGELIST {.stdcall, importc, header: "<commctrl.h>".}
proc ImageList_ReplaceIcon(images: HIMAGELIST, index: int32,
    icon: HICON): int32 {.stdcall, importc, header: "<commctrl.h>".}
proc ImageList_Destroy(images: HIMAGELIST): BOOL
    {.stdcall, importc, header: "<commctrl.h>".}
proc InvalidateRect(hwnd: HWND, rect: ptr RECT, erase: BOOL): BOOL {.stdcall, importc, header: "<windows.h>".}
proc SetStretchBltMode(dc: HDC, mode: int32): int32 {.stdcall, importc, header: "<windows.h>".}
proc StretchDIBits(dc: HDC, x, y, dw, dh, sx, sy, sw, sh: int32,
    bits: pointer, info: ptr BITMAPINFO, usage, rop: DWORD): int32 {.stdcall, importc, header: "<windows.h>".}
proc MoveToEx(dc: HDC, x, y: int32, old: pointer): BOOL {.stdcall, importc, header: "<windows.h>".}
proc LineTo(dc: HDC, x, y: int32): BOOL {.stdcall, importc, header: "<windows.h>".}
proc SetTimer(hwnd: HWND, id: uint, ms: UINT, callback: pointer): uint {.stdcall, importc, header: "<windows.h>".}
proc KillTimer(hwnd: HWND, id: uint): BOOL {.stdcall, importc, header: "<windows.h>".}
proc GetOpenFileNameW(info: ptr OPENFILENAMEW): BOOL {.stdcall, importc, header: "<commdlg.h>".}
proc GetSaveFileNameW(info: ptr OPENFILENAMEW): BOOL {.stdcall, importc, header: "<commdlg.h>".}
proc MessageBoxW(hwnd: HWND, text, caption: WideCString, kind: UINT): int32 {.stdcall, importc, header: "<windows.h>".}
proc InitCommonControls() {.stdcall, importc, header: "<commctrl.h>".}
proc waveOutOpen(outHandle: ptr HWAVEOUT, device: uint, format: ptr WAVEFORMATEX,
    callback: uint, instance: uint, flags: DWORD): uint32 {.stdcall, importc.}
proc waveOutPrepareHeader(handle: HWAVEOUT, header: ptr WAVEHDR, size: UINT): uint32 {.stdcall, importc.}
proc waveOutWrite(handle: HWAVEOUT, header: ptr WAVEHDR, size: UINT): uint32 {.stdcall, importc.}
proc waveOutPause(handle: HWAVEOUT): uint32 {.stdcall, importc.}
proc waveOutRestart(handle: HWAVEOUT): uint32 {.stdcall, importc.}
proc waveOutReset(handle: HWAVEOUT): uint32 {.stdcall, importc.}
proc waveOutUnprepareHeader(handle: HWAVEOUT, header: ptr WAVEHDR, size: UINT): uint32 {.stdcall, importc.}
proc waveOutClose(handle: HWAVEOUT): uint32 {.stdcall, importc.}

var
  instance: HINSTANCE
  mainWindow, treeView, preview, textView, openButton, scaleCombo: HWND
  fontModeCombo, fontSample, fontGlyphCombo, fontDetails: HWND
  playButton, formatCombo, exportButton, progressBar: HWND
  bindings: seq[TreeBinding]
  selected: TreeBinding
  currentFilename: string
  currentInspection: VextInspection
  currentView = vkNone
  scaleChoice = 0
  fontGridMode = false
  fontSelectedGlyph = 0
  fontPreviewText: string
  animationFrame = 0
  animationPlaying = false
  colourCycleElapsedMs: int64
  audioPlaying = false
  audioPaused = false
  waveHandle: HWAVEOUT
  waveHeader: WAVEHDR
  waveData: seq[int16]
  firstPreviewItem: HTREEITEM
  treeImages: HIMAGELIST
  failureImageIndex = -1'i32
  loadThread: Thread[LoadJob]

proc lowWord(value: WPARAM): int = int(value and 0xffff)
proc highWord(value: WPARAM): int = int((value shr 16) and 0xffff)
proc w(value: string): WideCStringObj = newWideCString(value)

proc windowText(hwnd: HWND): string =
  let length = int(GetWindowTextLengthW(hwnd))
  if length <= 0: return
  var buffer = newSeq[Utf16Char](length + 1)
  discard GetWindowTextW(hwnd, cast[WideCString](addr buffer[0]), int32(length + 1))
  result = $cast[WideCString](addr buffer[0])

proc showError(message: string) =
  discard MessageBoxW(mainWindow, w(message), w("Vexter"), 0x10)

proc layout(hwnd: HWND)

proc metadataString(node: VextResourceNode): string =
  result = &"Path: {node.path}\r\nType: {node.typeId}\r\n"
  for entry in node.metadata:
    let value = case entry.value.kind
      of vmvkInteger: $entry.value.integerValue
      of vmvkString: entry.value.stringValue
    result.add &"{entry.key}: {value}\r\n"

proc failureString(node: VextResourceNode): string =
  &"This contained file could not be decoded.\r\n\r\n" &
    &"Path: {node.path}\r\n" &
    &"Suspected format: {node.failureFormat}\r\n\r\n" &
    &"Decoder error:\r\n{node.failureMessage}\r\n"

proc stopAudio() =
  if waveHandle != nil:
    discard waveOutReset(waveHandle)
    discard waveOutUnprepareHeader(waveHandle, addr waveHeader, UINT(sizeof(WAVEHDR)))
    discard waveOutClose(waveHandle)
    waveHandle = nil
  waveData.setLen(0)
  audioPlaying = false
  audioPaused = false

proc currentRasterImage(maximumWidth = 0): VextTrueColourImage =
  if not selected.isNil and not selected.node.isNil and
      selected.node.kind == vrnkFont:
    if fontGridMode:
      return renderBitmapFontGlyphGrid(selected.node.font,
        max(1, maximumWidth), fontSelectedGlyph)
    return renderBitmapFontText(selected.node.font, fontPreviewText,
      max(1, maximumWidth))
  if not selected.isNil and not selected.node.isNil and
      selected.node.kind == vrnkPalette:
    return renderPaletteSwatch(selected.node.palette)
  if selected.isNil or selected.node.isNil or selected.node.kind != vrnkRaster:
    return
  let raster = selected.node.raster
  case raster.kind
  of vrkIndexedImage, vrkIndexedAnimation:
    let source = if raster.kind == vrkIndexedImage:
        if raster.image.colourCycles.len > 0:
          colourCycledImageAt(raster.image, raster.image.colourCycles,
            colourCycleElapsedMs)
        else: raster.image
      else: raster.animation.frames[animationFrame].image
    result.width = source.width
    result.height = source.height
    result.pixels = newSeq[VextRgb](source.width * source.height)
    result.alpha = source.alpha
    for i, pixel in source.pixels:
      if int(pixel) < source.palette.len:
        result.pixels[i] = source.palette[int(pixel)]
  of vrkTrueColourImage:
    result = raster.trueColourImage
  of vrkTrueColourAnimation:
    result = raster.trueColourAnimation.frames[animationFrame].image

proc paintPreview(hwnd: HWND) =
  var ps: PAINTSTRUCT
  let dc = BeginPaint(hwnd, addr ps)
  var area: RECT
  discard GetClientRect(hwnd, addr area)
  discard FillRect(dc, addr area, GetSysColorBrush(COLOR_WINDOW))
  if currentView in {vkRaster, vkFont}:
    let availableW = int(area.right - area.left)
    let availableH = int(area.bottom - area.top)
    let previewScale = if scaleChoice == 0: 1 else: scaleChoice
    let image = currentRasterImage(max(1, availableW div previewScale))
    if image.width > 0 and image.height > 0:
      var pixels = newSeq[byte](image.width * image.height * 4)
      for i, colour in image.pixels:
        let alpha = if image.alpha.len == pixels.len div 4: image.alpha[i] else: 255'u8
        let x = i mod image.width
        let y = i div image.width
        let background = if currentView == vkFont:
            (if (x div 8 + y div 8) mod 2 == 0: 56 else: 88)
          else: 255
        pixels[i * 4] = byte((int(colour.b) * int(alpha) + background * (255-int(alpha))) div 255)
        pixels[i * 4 + 1] = byte((int(colour.g) * int(alpha) + background * (255-int(alpha))) div 255)
        pixels[i * 4 + 2] = byte((int(colour.r) * int(alpha) + background * (255-int(alpha))) div 255)
        pixels[i * 4 + 3] = 0
      var info: BITMAPINFO
      info.bmiHeader = BITMAPINFOHEADER(biSize: DWORD(sizeof(BITMAPINFOHEADER)),
        biWidth: int32(image.width), biHeight: -int32(image.height), biPlanes: 1,
        biBitCount: 32, biCompression: 0)
      var dw, dh: int
      if scaleChoice == 0:
        let factor = min(availableW.float / image.width.float,
          availableH.float / image.height.float)
        dw = max(1, int(image.width.float * factor))
        dh = max(1, int(image.height.float * factor))
      else:
        dw = image.width * scaleChoice
        dh = image.height * scaleChoice
      discard SetStretchBltMode(dc, COLORONCOLOR)
      discard StretchDIBits(dc, int32((availableW-dw) div 2),
        int32((availableH-dh) div 2), int32(dw), int32(dh), 0, 0,
        int32(image.width), int32(image.height), addr pixels[0], addr info,
        DIB_RGB_COLORS, SRCCOPY)
  elif currentView == vkAudio and not selected.isNil:
    let sound = selected.node.audioSound
    let channels = sound.buffer.channels
    if channels.len > 0 and channels[0].len > 0:
      let width = max(1, int(area.right-area.left))
      let height = int(area.bottom-area.top)
      discard MoveToEx(dc, 0, int32(height div 2), nil)
      for x in 0..<width:
        let first = x * channels[0].len div width
        let last = max(first+1, (x+1) * channels[0].len div width)
        var lo = high(int32)
        var hi = low(int32)
        for i in first..<min(last, channels[0].len):
          lo = min(lo, channels[0][i])
          hi = max(hi, channels[0][i])
        let denom = max(1.0, pow(2.0, sound.buffer.bitsPerSample.float-1))
        let y1 = height div 2 - int(hi.float / denom * (height.float * 0.45))
        let y2 = height div 2 - int(lo.float / denom * (height.float * 0.45))
        discard MoveToEx(dc, int32(x), int32(y1), nil)
        discard LineTo(dc, int32(x), int32(y2))
  discard EndPaint(hwnd, addr ps)

proc previewProc(hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  if msg == WM_PAINT:
    paintPreview(hwnd)
    return 0
  DefWindowProcW(hwnd, msg, wp, lp)

proc containsFailure(node: VextResourceNode): bool =
  if node.failureMessage.len > 0: return true
  for child in node.children:
    if child.containsFailure: return true

proc addTreeNode(node: VextResourceNode, parent: HTREEITEM): HTREEITEM =
  var label = if node.path.len == 0: node.typeId else: node.path.split('/')[^1]
  if node.failureMessage.len > 0 and failureImageIndex < 0:
    label = "[!] " & label
  let labelWide = w(label)
  let binding = TreeBinding(node: node)
  bindings.add binding
  let imageIndex = if node.failureMessage.len > 0:
      failureImageIndex else: I_IMAGENONE
  var insert = TVINSERTSTRUCTW(hParent: parent, hInsertAfter: TVI_LAST,
    item: TVITEMW(mask: TVIF_TEXT or TVIF_PARAM or TVIF_IMAGE or
      TVIF_SELECTEDIMAGE, pszText: labelWide, iImage: imageIndex,
      iSelectedImage: imageIndex,
      lParam: cast[LPARAM](binding)))
  result = cast[HTREEITEM](SendMessageW(treeView, TVM_INSERTITEMW, 0,
    cast[LPARAM](addr insert)))
  if firstPreviewItem == nil and node.kind in
      {vrnkRaster, vrnkPalette, vrnkFont, vrnkAudio, vrnkText} or
      node.failureMessage.len > 0:
    firstPreviewItem = result
  for child in node.children:
    discard addTreeNode(child, result)
  if node.metadata.len > 0:
    let metadata = TreeBinding(node: node, metadataText: metadataString(node))
    let metadataLabel = w("Metadata")
    bindings.add metadata
    var metadataInsert = TVINSERTSTRUCTW(hParent: result, hInsertAfter: TVI_LAST,
      item: TVITEMW(mask: TVIF_TEXT or TVIF_PARAM, pszText: metadataLabel,
        lParam: cast[LPARAM](metadata)))
    discard SendMessageW(treeView, TVM_INSERTITEMW, 0,
      cast[LPARAM](addr metadataInsert))
  if node.children.len > 0 and node.containsFailure:
    discard SendMessageW(treeView, TVM_EXPAND, TVE_EXPAND,
      cast[LPARAM](result))

proc rebuildTree() =
  discard SendMessageW(treeView, TVM_DELETEITEM, 0, cast[LPARAM](TVI_ROOT))
  bindings.setLen(0)
  firstPreviewItem = nil
  for root in currentInspection.resources.roots:
    let item = addTreeNode(root, TVI_ROOT)
    discard SendMessageW(treeView, TVM_EXPAND, TVE_EXPAND, cast[LPARAM](item))
  if firstPreviewItem != nil:
    discard SendMessageW(treeView, TVM_SELECTITEM, TVGN_CARET,
      cast[LPARAM](firstPreviewItem))

proc isPlayable(binding: TreeBinding): bool =
  if binding.isNil or binding.metadataText.len > 0:
    return false
  case binding.node.kind
  of vrnkAudio:
    binding.node.audioSound.buffer.sampleCount > 0
  of vrnkRaster:
    binding.node.raster.kind in {vrkIndexedAnimation,
      vrkTrueColourAnimation} or
      (binding.node.raster.kind == vrkIndexedImage and
       binding.node.raster.image.colourCycles.len > 0)
  else:
    false

proc glyphDetails(font: VextBitmapFont, glyphIndex: int): string =
  result = &"Font: {font.name}\r\nGlyphs: {font.glyphs.len}  " &
    &"Mappings: {font.mappings.len}  Line height: {font.lineHeight}  " &
    &"Baseline: {font.baseline}  Ascent: {font.ascent}  Descent: {font.descent}\r\n"
  result.add &"Kerning pairs: {font.kerning.len}  Substitutions: " &
    &"{font.substitutions.len}  Ligatures: {font.ligatures.len}\r\n"
  if glyphIndex < 0 or glyphIndex >= font.glyphs.len: return
  let glyph = font.glyphs[glyphIndex]
  result.add &"Glyph {glyphIndex}: source index {glyph.sourceIndex}"
  if glyph.name.len > 0: result.add &"  name: {glyph.name}"
  result.add &"\r\nBitmap: {width(glyph.bitmap)}x{height(glyph.bitmap)}  " &
    &"bearing: ({glyph.bearingX}, {glyph.bearingY})  " &
    &"advance: ({glyph.advanceX}, {glyph.advanceY})\r\nMappings:"
  var found = false
  for mapping in font.mappings:
    if mapping.glyphIndex == glyphIndex:
      result.add &" U+{mapping.codePoint:04X}"
      found = true
  if not found: result.add " (unmapped/custom/default)"

proc fontSummaryDetails(font: VextBitmapFont): string =
  result = &"Font: {font.name}\r\nGlyphs: {font.glyphs.len}  " &
    &"Mappings: {font.mappings.len}  Line height: {font.lineHeight}  " &
    &"Baseline: {font.baseline}  Ascent: {font.ascent}  Descent: {font.descent}\r\n"
  result.add "\r\nMappings:"
  if font.mappings.len == 0:
    result.add " (none)"
  else:
    for mapping in font.mappings:
      result.add &" U+{mapping.codePoint:04X}->glyph {mapping.glyphIndex}"
  result.add "\r\nKerning:"
  if font.kerning.len == 0:
    result.add " (none)"
  else:
    for pair in font.kerning:
      result.add &" U+{pair.leftCodePoint:04X}/U+{pair.rightCodePoint:04X}" &
        &"=({pair.amountX},{pair.amountY})"
  result.add "\r\nSubstitutions:"
  if font.substitutions.len == 0:
    result.add " (none)"
  else:
    for substitution in font.substitutions:
      result.add &" U+{substitution.sourceCodePoint:04X}->" &
        &"U+{substitution.replacementCodePoint:04X}"
  result.add "\r\nLigatures:"
  if font.ligatures.len == 0:
    result.add " (none)"
  else:
    for ligature in font.ligatures:
      result.add " ["
      for index, codePoint in ligature.components:
        if index > 0: result.add "+"
        result.add &"U+{codePoint:04X}"
      result.add &"]->glyph {ligature.glyphIndex}"

proc populateFontControls(font: VextBitmapFont) =
  fontGridMode = false
  fontSelectedGlyph = 0
  fontPreviewText = font.defaultPreviewText
  discard SetWindowTextW(fontSample, w(fontPreviewText))
  discard SendMessageW(fontModeCombo, CB_SETCURSEL, 0, 0)
  discard SendMessageW(fontGlyphCombo, CB_RESETCONTENT, 0, 0)
  for index, glyph in font.glyphs:
    var label = &"{index}: source {glyph.sourceIndex}"
    var mappingCount = 0
    for mapping in font.mappings:
      if mapping.glyphIndex == index:
        label.add (if mappingCount == 0: "  " else: ", ")
        label.add &"U+{mapping.codePoint:04X}"
        inc mappingCount
    if mappingCount == 0: label.add "  unmapped"
    if glyph.name.len > 0: label.add "  " & glyph.name
    let wide = w(label)
    discard SendMessageW(fontGlyphCombo, CB_ADDSTRING, 0,
      cast[LPARAM](WideCString(wide)))
  if font.glyphs.len > 0:
    discard SendMessageW(fontGlyphCombo, CB_SETCURSEL, 0, 0)
  discard SetWindowTextW(fontDetails, w(fontSummaryDetails(font)))

proc selectBinding(binding: TreeBinding) =
  stopAudio()
  selected = binding
  animationFrame = 0
  colourCycleElapsedMs = 0
  animationPlaying = false
  discard KillTimer(mainWindow, 1)
  discard SendMessageW(formatCombo, CB_RESETCONTENT, 0, 0)
  if binding.isNil:
    currentView = vkNone
  elif binding.metadataText.len > 0:
    currentView = vkText
    discard SetWindowTextW(textView, w(binding.metadataText))
  elif binding.node.failureMessage.len > 0:
    currentView = vkText
    discard SetWindowTextW(textView, w(failureString(binding.node)))
  elif binding.node.kind == vrnkText:
    currentView = vkText
    discard SetWindowTextW(textView, w(binding.node.text))
  elif binding.node.kind in {vrnkRaster, vrnkPalette}:
    currentView = vkRaster
  elif binding.node.kind == vrnkFont:
    currentView = vkFont
    populateFontControls(binding.node.font)
  elif binding.node.kind == vrnkAudio:
    currentView = vkAudio
  else:
    currentView = vkText
    discard SetWindowTextW(textView, w(metadataString(binding.node)))
  let showText = currentView == vkText
  discard ShowWindow(textView, if showText: SW_SHOW else: 0)
  discard ShowWindow(preview, if showText: 0 else: SW_SHOW)
  let showFont = currentView == vkFont
  discard ShowWindow(fontModeCombo, if showFont: SW_SHOW else: 0)
  discard ShowWindow(fontSample,
    if showFont and not fontGridMode: SW_SHOW else: 0)
  discard ShowWindow(fontGlyphCombo,
    if showFont and fontGridMode: SW_SHOW else: 0)
  discard ShowWindow(fontDetails, if showFont: SW_SHOW else: 0)
  let playable = binding.isPlayable
  discard EnableWindow(playButton, if playable: 1 else: 0)
  discard SetWindowTextW(playButton, w("Play"))
  if not binding.isNil and binding.metadataText.len == 0:
    let formats = binding.node.exportFormatsFor
    var defaultFormatIndex = 0
    for index, format in formats:
      let formatName = w(format.displayName)
      discard SendMessageW(formatCombo, CB_ADDSTRING, 0,
        cast[LPARAM](WideCString(formatName)))
      if format.isDefault:
        defaultFormatIndex = index
    discard SendMessageW(formatCombo, CB_SETCURSEL,
      WPARAM(defaultFormatIndex), 0)
    discard EnableWindow(exportButton, if formats.len > 0: 1 else: 0)
  else:
    discard EnableWindow(exportButton, 0)
  if preview != nil:
    layout(mainWindow)
    discard InvalidateRect(preview, nil, 1)

proc selectedFrameDuration(): int =
  if selected.isNil or selected.node.kind != vrnkRaster: return 0
  case selected.node.raster.kind
  of vrkIndexedImage:
    let ranges = selected.node.raster.image.colourCycles
    if ranges.len == 0: 0
    else: int(colourCycleNextBoundaryMs(ranges,
      colourCycleElapsedMs) - colourCycleElapsedMs)
  of vrkIndexedAnimation: selected.node.raster.animation.frames[animationFrame].durationMs
  of vrkTrueColourAnimation: selected.node.raster.trueColourAnimation.frames[animationFrame].durationMs
  else: 0

proc frameCount(): int =
  if selected.isNil or selected.node.kind != vrnkRaster: return 0
  case selected.node.raster.kind
  of vrkIndexedAnimation: selected.node.raster.animation.frames.len
  of vrkTrueColourAnimation: selected.node.raster.trueColourAnimation.frames.len
  of vrkIndexedImage:
    if selected.node.raster.image.colourCycles.len > 0: 2 else: 1
  else: 1

proc togglePlayback() =
  if currentView == vkRaster and frameCount() > 1:
    animationPlaying = not animationPlaying
    discard SetWindowTextW(playButton, w(if animationPlaying: "Pause" else: "Play"))
    if animationPlaying:
      discard SetTimer(mainWindow, 1, UINT(max(10, selectedFrameDuration())), nil)
    else:
      discard KillTimer(mainWindow, 1)
  elif currentView == vkAudio:
    if audioPlaying:
      if audioPaused:
        discard waveOutRestart(waveHandle)
      else:
        discard waveOutPause(waveHandle)
      audioPaused = not audioPaused
      discard SetWindowTextW(playButton, w(if audioPaused: "Play" else: "Pause"))
      return
    let sound = selected.node.audioSound
    let channels = sound.buffer.channels.len
    if channels == 0 or sound.buffer.sampleCount == 0: return
    waveData = newSeq[int16](sound.buffer.sampleCount * channels)
    for i in 0..<sound.buffer.sampleCount:
      for channel in 0..<channels:
        let source = sound.buffer.channels[channel][i]
        let normalized =
          if sound.buffer.bitsPerSample < 16:
            source shl (16 - sound.buffer.bitsPerSample)
          elif sound.buffer.bitsPerSample > 16:
            source shr (sound.buffer.bitsPerSample - 16)
          else:
            source
        waveData[i*channels+channel] = int16(clamp(normalized,
          -32768'i32, 32767'i32))
    var format = WAVEFORMATEX(wFormatTag: WAVE_FORMAT_PCM,
      nChannels: WORD(channels), nSamplesPerSec: DWORD(sound.sampleRate),
      nAvgBytesPerSec: DWORD(sound.sampleRate*channels*2),
      nBlockAlign: WORD(channels*2), wBitsPerSample: 16)
    if waveOutOpen(addr waveHandle, WAVE_MAPPER, addr format, 0, 0, 0) == 0:
      waveHeader = WAVEHDR(lpData: cast[cstring](addr waveData[0]),
        dwBufferLength: DWORD(waveData.len*2))
      if waveOutPrepareHeader(waveHandle, addr waveHeader, UINT(sizeof(WAVEHDR))) == 0:
        discard waveOutWrite(waveHandle, addr waveHeader, UINT(sizeof(WAVEHDR)))
        audioPlaying = true
        discard SetWindowTextW(playButton, w("Pause"))

proc chooseFile(save: bool, extension = "", filter = "All files\0*.*\0\0"): string =
  var buffer = newWideCString("", 32768)
  let filterWide = w(filter)
  let extensionWide = w(extension)
  var info = OPENFILENAMEW(lStructSize: DWORD(sizeof(OPENFILENAMEW)),
    hwndOwner: mainWindow, lpstrFilter: filterWide, lpstrFile: buffer,
    nMaxFile: 32768, Flags: OFN_EXPLORER or OFN_PATHMUSTEXIST)
  if save:
    info.Flags = info.Flags or OFN_OVERWRITEPROMPT
    info.lpstrDefExt = extensionWide
  else:
    info.Flags = info.Flags or OFN_FILEMUSTEXIST
  let accepted = if save: GetSaveFileNameW(addr info) else: GetOpenFileNameW(addr info)
  if accepted != 0: $buffer else: ""

proc loadWorker(job: LoadJob) {.thread.} =
  var loaded = LoadResult(filename: job.filename)
  try:
    let contents = readFile(job.filename)
    var data = newSeq[byte](contents.len)
    for i, value in contents: data[i] = byte(value)
    {.cast(gcsafe).}:
      loaded.inspection = inspectSource(job.filename, data, progress =
        proc(event: VextProgressEvent): bool = true,
        companionResolver = proc(relativePath: string): seq[byte] {.gcsafe.} =
          let companionPath = job.filename.parentDir / relativePath
          if companionPath.fileExists:
            let companion = readFile(companionPath)
            result = newSeq[byte](companion.len)
            for index, value in companion: result[index] = byte(value))
  except CatchableError as error:
    loaded.error = error.msg
  job.result[] = loaded
  discard PostMessageW(mainWindow, WM_LOAD_DONE, 0, cast[LPARAM](job.result))

proc startLoad(filename: string) =
  discard EnableWindow(openButton, 0)
  discard ShowWindow(progressBar, SW_SHOW)
  discard SendMessageW(progressBar, PBM_SETMARQUEE, 1, 30)
  let result = cast[ptr LoadResult](allocShared0(sizeof(LoadResult)))
  createThread(loadThread, loadWorker, (filename, result))

proc finishLoad(result: ptr LoadResult) =
  joinThread(loadThread)
  let loaded = result[]
  reset(result[])
  deallocShared(result)
  discard SendMessageW(progressBar, PBM_SETMARQUEE, 0, 0)
  discard ShowWindow(progressBar, 0)
  discard EnableWindow(openButton, 1)
  if loaded.error.len > 0:
    showError(loaded.error)
  else:
    stopAudio()
    selected = nil
    currentFilename = loaded.filename
    currentInspection = loaded.inspection
    rebuildTree()
    discard SetWindowTextW(mainWindow, w("Vexter - " & loaded.filename.extractFilename))

proc doExport() =
  if selected.isNil or selected.metadataText.len > 0: return
  let formats = selected.node.exportFormatsFor
  let index = int(SendMessageW(formatCombo, CB_GETCURSEL, 0, 0))
  if index < 0 or index >= formats.len: return
  let format = formats[index]
  let destination = chooseFile(true, format.extensions[0],
    format.displayName & "\0*." & format.extensions[0] & "\0All files\0*.*\0\0")
  if destination.len == 0: return
  try:
    var allowLarge = false
    var exported: VextExportResult
    while true:
      try:
        exported = exportResource(currentInspection.resources,
          VextExportRequest(resourcePath: selected.node.path,
            outputFormat: format.id,
            suggestedName: destination.splitFile.name,
            allowLargeAnimation: allowLarge))
        break
      except ValueError as error:
        if allowLarge or "explicitly allow a large animation" notin error.msg:
          raise
        let answer = MessageBoxW(mainWindow, w(error.msg &
          "\n\nContinue with this potentially expensive export?"),
          w("Vexter"), 0x34)
        if answer != 6: return
        allowLarge = true
    if exported.warnings.len > 0:
      var message = "This export cannot preserve:\n\n"
      for warning in exported.warnings:
        message.add "- " & warning & "\n"
      message.add "\nContinue with the export?"
      if MessageBoxW(mainWindow, w(message), w("Vexter export warning"),
          0x34) != 6:
        return
    for artifactIndex, artifact in exported.artifacts.artifacts:
      let artifactDestination = if artifactIndex == 0: destination
        else: destination.parentDir / artifact.suggestedFilename
      if artifactIndex > 0 and fileExists(artifactDestination):
        raise newException(ValueError,
          "companion output already exists: " & artifactDestination)
    for artifactIndex, artifact in exported.artifacts.artifacts:
      let artifactDestination = if artifactIndex == 0: destination
        else: destination.parentDir / artifact.suggestedFilename
      var contents = newString(artifact.data.len)
      for i, value in artifact.data: contents[i] = char(value)
      writeFile(artifactDestination, contents)
  except CatchableError as error:
    showError(error.msg)

proc layout(hwnd: HWND) =
  var rect: RECT
  discard GetClientRect(hwnd, addr rect)
  let width = int(rect.right)
  let height = int(rect.bottom)
  let toolbar = 34
  let treeWidth = max(180, width div 3)
  discard MoveWindow(openButton, 6, 5, 70, 24, 1)
  discard MoveWindow(progressBar, 84, 8, 220, 18, 1)
  discard MoveWindow(treeView, 6, int32(toolbar), int32(treeWidth-9), int32(height-toolbar-6), 1)
  discard MoveWindow(scaleCombo, int32(treeWidth+5), 5, 80, 200, 1)
  discard MoveWindow(playButton, int32(treeWidth+91), 5, 70, 24, 1)
  discard MoveWindow(formatCombo, int32(max(treeWidth+167, width-270)), 5, 170, 200, 1)
  discard MoveWindow(exportButton, int32(width-94), 5, 88, 24, 1)
  let contentX = treeWidth + 3
  let contentWidth = width - treeWidth - 9
  if currentView == vkFont:
    discard MoveWindow(fontModeCombo, int32(contentX), int32(toolbar), 100, 200, 1)
    discard MoveWindow(fontSample, int32(contentX + 106), int32(toolbar),
      int32(max(1, contentWidth - 106)), 24, 1)
    discard MoveWindow(fontGlyphCombo, int32(contentX + 106), int32(toolbar),
      int32(max(1, contentWidth - 106)), 240, 1)
    discard MoveWindow(preview, int32(contentX), int32(toolbar + 30),
      int32(contentWidth), int32(max(1, height - toolbar - 146)), 1)
    discard MoveWindow(fontDetails, int32(contentX), int32(max(toolbar + 30,
      height - 110)), int32(contentWidth), 104, 1)
  else:
    discard MoveWindow(preview, int32(contentX), int32(toolbar),
      int32(contentWidth), int32(height-toolbar-6), 1)
  discard MoveWindow(textView, int32(treeWidth+3), int32(toolbar), int32(width-treeWidth-9), int32(height-toolbar-6), 1)
  discard InvalidateRect(preview, nil, 1)

proc mainProc(hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  case msg
  of WM_CREATE:
    mainWindow = hwnd
    openButton = CreateWindowExW(0, w("BUTTON"), w("Open..."), WS_CHILD or WS_VISIBLE,
      0, 0, 0, 0, hwnd, cast[HMENU](1001), instance, nil)
    treeView = CreateWindowExW(0, w("SysTreeView32"), w(""), WS_CHILD or WS_VISIBLE or
      WS_BORDER or TVS_HASBUTTONS or TVS_HASLINES or TVS_LINESATROOT,
      0, 0, 0, 0, hwnd, cast[HMENU](1002), instance, nil)
    treeImages = ImageList_Create(16, 16, ILC_COLOR32 or ILC_MASK, 1, 1)
    if treeImages != nil:
      let warningIcon = LoadIconW(nil, IDI_WARNING)
      if warningIcon != nil:
        failureImageIndex = ImageList_ReplaceIcon(treeImages, -1, warningIcon)
      if failureImageIndex >= 0:
        discard SendMessageW(treeView, TVM_SETIMAGELIST, TVSIL_NORMAL,
          cast[LPARAM](treeImages))
    preview = CreateWindowExW(0, w("VexterPreview"), w(""), WS_CHILD or WS_VISIBLE or WS_BORDER,
      0, 0, 0, 0, hwnd, cast[HMENU](1003), instance, nil)
    textView = CreateWindowExW(0, w("EDIT"), w(""), WS_CHILD or WS_BORDER or WS_VSCROLL or
      ES_MULTILINE or ES_AUTOVSCROLL or ES_READONLY, 0, 0, 0, 0, hwnd,
      cast[HMENU](1004), instance, nil)
    fontModeCombo = CreateWindowExW(0, w("COMBOBOX"), w(""), WS_CHILD or
      CBS_DROPDOWNLIST, 0, 0, 0, 0, hwnd, cast[HMENU](1010), instance, nil)
    for label in ["Text", "Glyph grid"]:
      let wide = w(label)
      discard SendMessageW(fontModeCombo, CB_ADDSTRING, 0,
        cast[LPARAM](WideCString(wide)))
    fontSample = CreateWindowExW(0, w("EDIT"), w(""), WS_CHILD or WS_BORDER or
      ES_AUTOHSCROLL, 0, 0, 0, 0, hwnd, cast[HMENU](1011), instance, nil)
    fontGlyphCombo = CreateWindowExW(0, w("COMBOBOX"), w(""), WS_CHILD or
      CBS_DROPDOWNLIST or WS_VSCROLL, 0, 0, 0, 0, hwnd,
      cast[HMENU](1012), instance, nil)
    fontDetails = CreateWindowExW(0, w("EDIT"), w(""), WS_CHILD or WS_BORDER or
      ES_MULTILINE or ES_AUTOVSCROLL or ES_READONLY, 0, 0, 0, 0, hwnd,
      cast[HMENU](1013), instance, nil)
    scaleCombo = CreateWindowExW(0, w("COMBOBOX"), w(""), WS_CHILD or WS_VISIBLE or CBS_DROPDOWNLIST,
      0, 0, 0, 0, hwnd, cast[HMENU](1005), instance, nil)
    for label in ["Fit", "1x", "2x", "3x", "4x"]:
      let scaleLabel = w(label)
      discard SendMessageW(scaleCombo, CB_ADDSTRING, 0,
        cast[LPARAM](WideCString(scaleLabel)))
    discard SendMessageW(scaleCombo, CB_SETCURSEL, 0, 0)
    playButton = CreateWindowExW(0, w("BUTTON"), w("Play"), WS_CHILD or WS_VISIBLE,
      0, 0, 0, 0, hwnd, cast[HMENU](1006), instance, nil)
    formatCombo = CreateWindowExW(0, w("COMBOBOX"), w(""), WS_CHILD or WS_VISIBLE or CBS_DROPDOWNLIST,
      0, 0, 0, 0, hwnd, cast[HMENU](1007), instance, nil)
    exportButton = CreateWindowExW(0, w("BUTTON"), w("Export..."), WS_CHILD or WS_VISIBLE,
      0, 0, 0, 0, hwnd, cast[HMENU](1008), instance, nil)
    progressBar = CreateWindowExW(0, w("msctls_progress32"), w(""), WS_CHILD or PBST_MARQUEE,
      0, 0, 0, 0, hwnd, cast[HMENU](1009), instance, nil)
    discard EnableWindow(playButton, 0)
    discard EnableWindow(exportButton, 0)
    layout(hwnd)
    if paramCount() > 0:
      startLoad(paramStr(1))
    return 0
  of WM_SIZE:
    layout(hwnd)
    return 0
  of WM_COMMAND:
    case lowWord(wp)
    of 1001:
      let filename = chooseFile(false)
      if filename.len > 0: startLoad(filename)
    of 1005:
      if highWord(wp) == 1:
        scaleChoice = int(SendMessageW(scaleCombo, CB_GETCURSEL, 0, 0))
        discard InvalidateRect(preview, nil, 1)
    of 1006: togglePlayback()
    of 1008: doExport()
    of 1010:
      if highWord(wp) == 1 and currentView == vkFont:
        fontGridMode = SendMessageW(fontModeCombo, CB_GETCURSEL, 0, 0) == 1
        discard ShowWindow(fontSample, if fontGridMode: 0 else: SW_SHOW)
        discard ShowWindow(fontGlyphCombo, if fontGridMode: SW_SHOW else: 0)
        if not selected.isNil:
          let details = if fontGridMode:
            glyphDetails(selected.node.font, fontSelectedGlyph)
          else:
            fontSummaryDetails(selected.node.font)
          discard SetWindowTextW(fontDetails, w(details))
        layout(hwnd)
        discard InvalidateRect(preview, nil, 1)
    of 1011:
      if highWord(wp) == 0x0300 and currentView == vkFont:
        fontPreviewText = windowText(fontSample)
        discard InvalidateRect(preview, nil, 1)
    of 1012:
      if highWord(wp) == 1 and currentView == vkFont and not selected.isNil:
        fontSelectedGlyph = int(SendMessageW(fontGlyphCombo, CB_GETCURSEL, 0, 0))
        discard SetWindowTextW(fontDetails,
          w(glyphDetails(selected.node.font, fontSelectedGlyph)))
        discard InvalidateRect(preview, nil, 1)
    else: discard
    return 0
  of WM_NOTIFY:
    let notification = cast[ptr NMTREEVIEWW](lp)
    if notification != nil and notification.hdr.hwndFrom == treeView and
        notification.hdr.code == TVN_SELCHANGEDW:
      selectBinding(cast[TreeBinding](notification.itemNew.lParam))
    return 0
  of WM_TIMER:
    if wp == 1 and animationPlaying and frameCount() > 1:
      if selected.node.raster.kind == vrkIndexedImage:
        let
          ranges = selected.node.raster.image.colourCycles
          duration = selectedFrameDuration()
          period = colourCyclePeriodMs(ranges)
        colourCycleElapsedMs = (colourCycleElapsedMs + int64(duration)) mod period
      else:
        animationFrame = (animationFrame + 1) mod frameCount()
      discard InvalidateRect(preview, nil, 0)
      discard KillTimer(mainWindow, 1)
      discard SetTimer(mainWindow, 1, UINT(max(10, selectedFrameDuration())), nil)
    return 0
  of WM_LOAD_DONE:
    finishLoad(cast[ptr LoadResult](lp))
    return 0
  of WM_CLOSE:
    stopAudio()
  of WM_DESTROY:
    if treeImages != nil:
      discard SendMessageW(treeView, TVM_SETIMAGELIST, TVSIL_NORMAL, 0)
      discard ImageList_Destroy(treeImages)
      treeImages = nil
    PostQuitMessage(0)
    return 0
  else: discard
  DefWindowProcW(hwnd, msg, wp, lp)

proc GetModuleHandleW(name: WideCString): HINSTANCE {.stdcall, importc, header: "<windows.h>".}

proc run() =
  InitCommonControls()
  instance = GetModuleHandleW(nil)
  let previewClassName = w("VexterPreview")
  var previewClass = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)),
    style: CS_HREDRAW or CS_VREDRAW,
    lpfnWndProc: cast[pointer](previewProc), hInstance: instance,
    hCursor: LoadCursorW(nil, IDC_ARROW), hbrBackground: GetSysColorBrush(COLOR_WINDOW),
    lpszClassName: previewClassName)
  let previewAtom = RegisterClassExW(addr previewClass)
  if previewAtom == 0:
    raise newException(OSError, "could not register the Vexter preview class " &
      "(Win32 error " & $GetLastError() & ")")
  let mainClassName = w("VexterMain")
  var mainClass = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)),
    lpfnWndProc: cast[pointer](mainProc), hInstance: instance,
    hCursor: LoadCursorW(nil, IDC_ARROW), hbrBackground: GetSysColorBrush(COLOR_BTNFACE),
    lpszClassName: mainClassName)
  let mainAtom = RegisterClassExW(addr mainClass)
  if mainAtom == 0:
    raise newException(OSError, "could not register the Vexter main class " &
      "(Win32 error " & $GetLastError() & ")")
  let window = CreateWindowExW(0, w("VexterMain"), w("Vexter"),
    WS_OVERLAPPEDWINDOW or WS_CLIPCHILDREN,
    CW_USEDEFAULT, CW_USEDEFAULT, 1000, 700,
    nil, nil, instance, nil)
  if window == nil:
    raise newException(OSError, "could not create the Vexter main window (Win32 error " &
      $GetLastError() & ")")
  discard ShowWindow(window, SW_SHOW)
  discard UpdateWindow(window)
  var message: MSG
  while GetMessageW(addr message, nil, 0, 0) > 0:
    discard TranslateMessage(addr message)
    discard DispatchMessageW(addr message)

run()
