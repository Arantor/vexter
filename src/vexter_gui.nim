## Native dependency-free Windows viewer for vexterlib.

when not defined(windows):
  {.error: "vexter_gui is available only when targeting Windows".}

import std/[math, os, strformat, strutils, widestrs]
import vexterlib
import vexterlib/gui_preview

{.passC: "-D_WIN32_WINNT=0x0601 -DWINVER=0x0601 -include windows.h".}
{.passL: "-lcomctl32 -lcomdlg32 -lgdi32 -lwinmm -lshell32 -lole32".}
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
  HFONT = pointer
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
  POINT {.importc: "POINT", header: "<windows.h>".} = object
    x, y: int32
  TVHITTESTINFO {.importc: "TVHITTESTINFO", header: "<commctrl.h>".} = object
    pt: POINT
    flags: UINT
    hItem: HTREEITEM
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
  SCROLLINFO {.importc: "SCROLLINFO", header: "<windows.h>".} = object
    cbSize, fMask: UINT
    nMin, nMax: int32
    nPage: UINT
    nPos, nTrackPos: int32
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
  BROWSEINFOW {.importc: "BROWSEINFOW", header: "<shlobj.h>".} = object
    hwndOwner: HWND
    pidlRoot: pointer
    pszDisplayName: WideCString
    lpszTitle: WideCString
    ulFlags: UINT
    lpfn: pointer
    lParam: LPARAM
    iImage: int32

  ViewKind = enum vkNone, vkRaster, vkFont, vkAudio, vkText
  TreeBinding = ref object
    node: VextResourceNode
    descriptor: VextResourceDescriptor
    loadedTree: VextResourceTree
    loadedData: seq[byte]
    childrenLoaded: bool
    loadPending: bool
    workingLimitApproved: bool
    placeholder: bool
    metadataText: string
  LoadResult = object
    session: VextInspectionSession
    filename: string
    error: string
  LoadJob = tuple[filename: string, result: ptr LoadResult]
  ExtractionResult = object
    files: int
    warnings: seq[string]
    error: string
  ExtractionJob = tuple[session: VextInspectionSession, destination: string,
    overwrite: bool, result: ptr ExtractionResult]
  SessionJobKind = enum sjkExpand, sjkLoad, sjkDecodeLoaded
  SessionResult = object
    kind: SessionJobKind
    binding: TreeBinding
    item: HTREEITEM
    delta: VextResourceDelta
    loaded: VextLoadedResource
    decodeResult: VextDemandDecodeResult
    error: string
  SessionJob = tuple[kind: SessionJobKind, session: VextInspectionSession,
    binding: TreeBinding, item: HTREEITEM, maximumWorkingBytes: int,
    result: ptr SessionResult]
  PendingSessionJob = object
    kind: SessionJobKind
    binding: TreeBinding
    item: HTREEITEM
    maximumWorkingBytes: int

const
  WS_OVERLAPPEDWINDOW = 0x00CF0000'u32
  WS_CHILD = 0x40000000'u32
  WS_VISIBLE = 0x10000000'u32
  WS_CLIPCHILDREN = 0x02000000'u32
  WS_BORDER = 0x00800000'u32
  WS_VSCROLL = 0x00200000'u32
  WS_HSCROLL = 0x00100000'u32
  ES_MULTILINE = 0x0004'u32
  ES_AUTOVSCROLL = 0x0040'u32
  ES_READONLY = 0x0800'u32
  ES_AUTOHSCROLL = 0x0080'u32
  CBS_DROPDOWNLIST = 0x0003'u32
  TVS_HASBUTTONS = 0x0001'u32
  TVS_HASLINES = 0x0002'u32
  TVS_LINESATROOT = 0x0004'u32
  TVS_SHOWSELALWAYS = 0x0020'u32
  PBST_MARQUEE = 0x0008'u32
  CW_USEDEFAULT = low(int32)
  SW_SHOW = 5
  WM_CREATE = 0x0001'u32
  WM_DESTROY = 0x0002'u32
  WM_SIZE = 0x0005'u32
  WM_PAINT = 0x000F'u32
  WM_HSCROLL = 0x0114'u32
  WM_VSCROLL = 0x0115'u32
  WM_CLOSE = 0x0010'u32
  WM_SETFONT = 0x0030'u32
  WM_COMMAND = 0x0111'u32
  WM_TIMER = 0x0113'u32
  WM_NOTIFY = 0x004E'u32
  WM_APP = 0x8000'u32
  WM_LOAD_DONE = WM_APP + 1
  WM_SESSION_DONE = WM_APP + 2
  WM_SESSION_PROGRESS = WM_APP + 3
  WM_EXTRACTION_DONE = WM_APP + 4
  CB_ADDSTRING = 0x0143'u32
  CB_RESETCONTENT = 0x014B'u32
  CB_SETCURSEL = 0x014E'u32
  CB_GETCURSEL = 0x0147'u32
  PBM_SETMARQUEE = 0x040A'u32 # PBM_SETMARQUEE is WM_USER + 10.
  PBM_SETPOS = 0x0402'u32
  BIF_RETURNONLYFSDIRS = 0x0001'u32
  BIF_NEWDIALOGSTYLE = 0x0040'u32
  TVM_INSERTITEMW = 0x1132'u32
  TVM_DELETEITEM = 0x1101'u32
  TVM_SETIMAGELIST = 0x1109'u32
  TVM_GETNEXTITEM = 0x110A'u32
  TVM_GETITEMW = 0x113E'u32
  TVM_SETITEMW = 0x113F'u32
  TVM_HITTEST = 0x1111'u32
  TVM_EXPAND = 0x1102'u32
  TVGN_CHILD = 0x0004
  TVE_EXPAND = 0x0002
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
  TVN_ITEMEXPANDINGW = cast[UINT](-455'i32)
  NM_RCLICK = cast[UINT](-5'i32)
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
  HALFTONE = 4
  WHDR_DONE = 0x00000001'u32
  SB_HORZ = 0
  SB_VERT = 1
  SB_BOTH = 3
  SB_LINEUP = 0
  SB_LINEDOWN = 1
  SB_PAGEUP = 2
  SB_PAGEDOWN = 3
  SB_THUMBTRACK = 5
  SB_TOP = 6
  SB_BOTTOM = 7
  SIF_RANGE = 0x0001'u32
  SIF_PAGE = 0x0002'u32
  SIF_POS = 0x0004'u32
  SIF_TRACKPOS = 0x0010'u32
  SIF_ALL = SIF_RANGE or SIF_PAGE or SIF_POS or SIF_TRACKPOS
  SM_CXVSCROLL = 2
  SM_CYHSCROLL = 3
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
proc GetSystemMetrics(index: int32): int32 {.stdcall, importc, header: "<windows.h>".}
proc ShowScrollBar(hwnd: HWND, bar: int32, show: BOOL): BOOL {.stdcall, importc, header: "<windows.h>".}
proc GetScrollInfo(hwnd: HWND, bar: int32, info: ptr SCROLLINFO): BOOL {.stdcall, importc, header: "<windows.h>".}
proc SetScrollInfo(hwnd: HWND, bar: int32, info: ptr SCROLLINFO, redraw: BOOL): int32 {.stdcall, importc, header: "<windows.h>".}
proc SetStretchBltMode(dc: HDC, mode: int32): int32 {.stdcall, importc, header: "<windows.h>".}
proc SetBrushOrgEx(dc: HDC, x, y: int32, old: pointer): BOOL
    {.stdcall, importc, header: "<windows.h>".}
proc StretchDIBits(dc: HDC, x, y, dw, dh, sx, sy, sw, sh: int32,
    bits: pointer, info: ptr BITMAPINFO, usage, rop: DWORD): int32 {.stdcall, importc, header: "<windows.h>".}
proc MoveToEx(dc: HDC, x, y: int32, old: pointer): BOOL {.stdcall, importc, header: "<windows.h>".}
proc LineTo(dc: HDC, x, y: int32): BOOL {.stdcall, importc, header: "<windows.h>".}
proc SetTimer(hwnd: HWND, id: uint, ms: UINT, callback: pointer): uint {.stdcall, importc, header: "<windows.h>".}
proc KillTimer(hwnd: HWND, id: uint): BOOL {.stdcall, importc, header: "<windows.h>".}
proc GetOpenFileNameW(info: ptr OPENFILENAMEW): BOOL {.stdcall, importc, header: "<commdlg.h>".}
proc GetSaveFileNameW(info: ptr OPENFILENAMEW): BOOL {.stdcall, importc, header: "<commdlg.h>".}
proc MessageBoxW(hwnd: HWND, text, caption: WideCString, kind: UINT): int32 {.stdcall, importc, header: "<windows.h>".}
proc SHBrowseForFolderW(info: ptr BROWSEINFOW): pointer
    {.stdcall, importc, header: "<shlobj.h>".}
proc SHGetPathFromIDListW(id: pointer, path: WideCString): BOOL
    {.stdcall, importc, header: "<shlobj.h>".}
proc CoTaskMemFree(memory: pointer) {.stdcall, importc, header: "<objbase.h>".}
proc GetCursorPos(point: ptr POINT): BOOL {.stdcall, importc, header: "<windows.h>".}
proc ScreenToClient(hwnd: HWND, point: ptr POINT): BOOL {.stdcall, importc, header: "<windows.h>".}
proc CreatePopupMenu(): HMENU {.stdcall, importc, header: "<windows.h>".}
proc AppendMenuW(menu: HMENU, flags: UINT, id: uint,
    label: WideCString): BOOL {.stdcall, importc, header: "<windows.h>".}
proc TrackPopupMenu(menu: HMENU, flags: UINT, x, y: int32,
    reserved: int32, hwnd: HWND, rect: pointer): int32
    {.stdcall, importc, header: "<windows.h>".}
proc DestroyMenu(menu: HMENU): BOOL {.stdcall, importc, header: "<windows.h>".}
proc CreateFontW(height, width, escapement, orientation, weight: int32,
    italic, underline, strikeOut, charSet, outputPrecision, clipPrecision,
    quality, pitchAndFamily: DWORD, faceName: WideCString): HFONT
    {.stdcall, importc, header: "<windows.h>".}
proc DeleteObject(handle: pointer): BOOL
    {.stdcall, importc, header: "<windows.h>".}
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
  playButton, formatCombo, exportButton, extractButton, progressBar: HWND
  bindings: seq[TreeBinding]
  selected: TreeBinding
  metadataViewBinding: TreeBinding
  currentFilename: string
  currentSession: VextInspectionSession
  currentView = vkNone
  scaleChoice = 0
  previewHScroll = false
  previewVScroll = false
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
  uiFont, textFont: HFONT
  failureImageIndex = -1'i32
  loadThread: Thread[LoadJob]
  sessionThread: Thread[SessionJob]
  sessionJobActive = false
  sessionQueue: seq[PendingSessionJob]
  extractionThread: Thread[ExtractionJob]
  extractionActive = false

proc lowWord(value: WPARAM): int = int(value and 0xffff)
proc highWord(value: WPARAM): int = int((value shr 16) and 0xffff)
proc w(value: string): WideCStringObj = newWideCString(value)

proc setControlFont(control: HWND, font: HFONT) =
  if control != nil and font != nil:
    discard SendMessageW(control, WM_SETFONT, cast[WPARAM](font), 1)

proc windowText(hwnd: HWND): string =
  let length = int(GetWindowTextLengthW(hwnd))
  if length <= 0: return
  var buffer = newSeq[Utf16Char](length + 1)
  discard GetWindowTextW(hwnd, cast[WideCString](addr buffer[0]), int32(length + 1))
  result = $cast[WideCString](addr buffer[0])

proc showError(message: string) =
  discard MessageBoxW(mainWindow, w(message), w("Vexter"), 0x10)

proc byteSize(value: int): string =
  const units = ["bytes", "KiB", "MiB", "GiB", "TiB"]
  var amount = float(value)
  var unit = 0
  while amount >= 1024.0 and unit < units.high:
    amount /= 1024.0
    inc unit
  if unit == 0: &"{value} {units[unit]}"
  else: &"{amount:.1f} {units[unit]}"

proc layout(hwnd: HWND)
proc stopAudio()
proc selectBinding(binding: TreeBinding)

proc resetPreviewScrollPosition() =
  if preview == nil: return
  var info = SCROLLINFO(cbSize: UINT(sizeof(SCROLLINFO)), fMask: SIF_POS)
  discard SetScrollInfo(preview, SB_HORZ, addr info, 0)
  discard SetScrollInfo(preview, SB_VERT, addr info, 0)

proc metadataString(node: VextResourceNode): string =
  result = &"Path: {node.path}\r\nType: {node.typeId}\r\n"
  for entry in node.metadata:
    let value = case entry.value.kind
      of vmvkInteger: $entry.value.integerValue
      of vmvkString: entry.value.stringValue
    result.add &"{entry.key}: {value}\r\n"

proc metadataString(item: VextResourceDescriptor): string =
  result = &"Path: {item.path}\r\nType: {item.typeId}\r\n"
  for entry in item.metadata:
    let value = case entry.value.kind
      of vmvkInteger: $entry.value.integerValue
      of vmvkString: entry.value.stringValue
    result.add &"{entry.key}: {value}\r\n"

proc showTreeMetadataMenu() =
  var cursor: POINT
  if GetCursorPos(addr cursor) == 0: return
  var hit = TVHITTESTINFO(pt: cursor)
  discard ScreenToClient(treeView, addr hit.pt)
  discard SendMessageW(treeView, TVM_HITTEST, 0, cast[LPARAM](addr hit))
  if hit.hItem == nil: return
  var treeItem = TVITEMW(mask: TVIF_PARAM, hItem: hit.hItem)
  if SendMessageW(treeView, TVM_GETITEMW, 0,
      cast[LPARAM](addr treeItem)) == 0:
    return
  let binding = cast[TreeBinding](treeItem.lParam)
  if binding.isNil or binding.placeholder: return
  let menu = CreatePopupMenu()
  if menu == nil: return
  let showingMetadata = metadataViewBinding == binding
  discard AppendMenuW(menu, 0, 1,
    w(if showingMetadata and not binding.node.isNil: "Show preview"
      else: "Show metadata"))
  var screenPoint: POINT
  discard GetCursorPos(addr screenPoint)
  let command = TrackPopupMenu(menu, 0x0102, screenPoint.x, screenPoint.y,
    0, mainWindow, nil)
  discard DestroyMenu(menu)
  if command == 1:
    if showingMetadata and not binding.node.isNil:
      selectBinding(binding)
    else:
      stopAudio()
      selected = binding
      metadataViewBinding = binding
      currentView = vkText
      let details = if not binding.node.isNil: metadataString(binding.node)
        else: metadataString(binding.descriptor)
      discard SetWindowTextW(textView, w(details))
      discard ShowWindow(textView, SW_SHOW)
      discard ShowWindow(preview, 0)
      discard ShowWindow(fontModeCombo, 0)
      discard ShowWindow(fontSample, 0)
      discard ShowWindow(fontGlyphCombo, 0)
      discard ShowWindow(fontDetails, 0)
      discard EnableWindow(playButton, 0)
      discard EnableWindow(exportButton, 0)
      layout(mainWindow)

proc failureString(node: VextResourceNode): string =
  &"This contained file could not be decoded.\r\n\r\n" &
    &"Path: {node.path}\r\n" &
    &"Suspected format: {node.failureFormat}\r\n\r\n" &
    &"Decoder error:\r\n{node.failureMessage}\r\n"

proc stopAudio() =
  if mainWindow != nil:
    discard KillTimer(mainWindow, 2)
  if waveHandle != nil:
    discard waveOutReset(waveHandle)
    discard waveOutUnprepareHeader(waveHandle, addr waveHeader, UINT(sizeof(WAVEHDR)))
    discard waveOutClose(waveHandle)
    waveHandle = nil
  waveData.setLen(0)
  audioPlaying = false
  audioPaused = false
  if playButton != nil:
    discard SetWindowTextW(playButton, w("Play"))

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
  if currentView notin {vkRaster, vkFont} and
      (previewHScroll or previewVScroll):
    discard ShowScrollBar(hwnd, SB_BOTH, 0)
    previewHScroll = false
    previewVScroll = false
  if currentView in {vkRaster, vkFont}:
    var availableW = int(area.right - area.left)
    var availableH = int(area.bottom - area.top)
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
        (dw, dh) = previewFitSize(image.width, image.height, availableW,
          availableH)
      else:
        dw = image.width * scaleChoice
        dh = image.height * scaleChoice
      var scrollX, scrollY = 0
      if scaleChoice == 0:
        discard ShowScrollBar(hwnd, SB_BOTH, 0)
        previewHScroll = false
        previewVScroll = false
      else:
        # Recover the unobstructed viewport before deciding whether either bar
        # is needed, so growing the window can remove an existing scrollbar.
        let scrollWidth = int(GetSystemMetrics(SM_CXVSCROLL))
        let scrollHeight = int(GetSystemMetrics(SM_CYHSCROLL))
        let fullW = availableW + (if previewVScroll: scrollWidth else: 0)
        let fullH = availableH + (if previewHScroll: scrollHeight else: 0)
        var needH = dw > fullW
        var needV = dh > fullH
        if needV: needH = dw > fullW - scrollWidth
        if needH: needV = dh > fullH - scrollHeight
        discard ShowScrollBar(hwnd, SB_HORZ, if needH: 1 else: 0)
        discard ShowScrollBar(hwnd, SB_VERT, if needV: 1 else: 0)
        previewHScroll = needH
        previewVScroll = needV
        var viewport: RECT
        discard GetClientRect(hwnd, addr viewport)
        let viewportW = max(1, int(viewport.right - viewport.left))
        let viewportH = max(1, int(viewport.bottom - viewport.top))
        availableW = viewportW
        availableH = viewportH
        var horizontal = SCROLLINFO(cbSize: UINT(sizeof(SCROLLINFO)),
          fMask: SIF_RANGE or SIF_PAGE, nMax: int32(max(0, dw - 1)),
          nPage: UINT(viewportW))
        var vertical = SCROLLINFO(cbSize: UINT(sizeof(SCROLLINFO)),
          fMask: SIF_RANGE or SIF_PAGE, nMax: int32(max(0, dh - 1)),
          nPage: UINT(viewportH))
        discard SetScrollInfo(hwnd, SB_HORZ, addr horizontal, 1)
        discard SetScrollInfo(hwnd, SB_VERT, addr vertical, 1)
        horizontal.fMask = SIF_POS
        vertical.fMask = SIF_POS
        discard GetScrollInfo(hwnd, SB_HORZ, addr horizontal)
        discard GetScrollInfo(hwnd, SB_VERT, addr vertical)
        scrollX = int(horizontal.nPos)
        scrollY = int(vertical.nPos)
      let indexedPreview = currentView == vkFont or
        (not selected.isNil and not selected.node.isNil and
          (selected.node.kind == vrnkPalette or
          (selected.node.kind == vrnkRaster and selected.node.raster.kind in
            {vrkIndexedImage, vrkIndexedAnimation})))
      let resampling = previewResampling(indexedPreview, image.width,
        image.height, dw, dh)
      if resampling == vprFiltered:
        discard SetStretchBltMode(dc, HALFTONE)
        discard SetBrushOrgEx(dc, 0, 0, nil)
      else:
        discard SetStretchBltMode(dc, COLORONCOLOR)
      let drawX = if dw <= availableW: (availableW-dw) div 2 else: -scrollX
      let drawY = if dh <= availableH: (availableH-dh) div 2 else: -scrollY
      discard StretchDIBits(dc, int32(drawX), int32(drawY), int32(dw), int32(dh), 0, 0,
        int32(image.width), int32(image.height), addr pixels[0], addr info,
        DIB_RGB_COLORS, SRCCOPY)
    elif previewHScroll or previewVScroll:
      discard ShowScrollBar(hwnd, SB_BOTH, 0)
      previewHScroll = false
      previewVScroll = false
  elif currentView == vkAudio and not selected.isNil:
    let sound = selected.node.audioSound
    let channels = sound.buffer.channels
    if channels.len > 0 and channels[0].len > 0:
      let width = max(1, int(area.right-area.left))
      let height = max(1, int(area.bottom-area.top))
      let denominator = max(1.0,
        pow(2.0, sound.buffer.bitsPerSample.float-1))
      # Give every channel its own lane. For ordinary stereo this presents
      # left above right instead of silently drawing only the left channel.
      for channelIndex, channel in channels:
        let laneTop = channelIndex * height div channels.len
        let laneBottom = (channelIndex + 1) * height div channels.len
        let laneHeight = max(1, laneBottom - laneTop)
        let centre = laneTop + laneHeight div 2
        discard MoveToEx(dc, 0, int32(centre), nil)
        discard LineTo(dc, int32(width), int32(centre))
        for x in 0..<width:
          let first = x * channel.len div width
          let last = max(first+1, (x+1) * channel.len div width)
          var lo = high(int32)
          var hi = low(int32)
          for i in first..<min(last, channel.len):
            lo = min(lo, channel[i])
            hi = max(hi, channel[i])
          let amplitude = laneHeight.float * 0.45
          let y1 = centre - int(hi.float / denominator * amplitude)
          let y2 = centre - int(lo.float / denominator * amplitude)
          discard MoveToEx(dc, int32(x), int32(y1), nil)
          discard LineTo(dc, int32(x), int32(y2))
  discard EndPaint(hwnd, addr ps)

proc previewProc(hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  if msg == WM_PAINT:
    paintPreview(hwnd)
    return 0
  if msg == WM_HSCROLL or msg == WM_VSCROLL:
    let bar = int32(if msg == WM_HSCROLL: SB_HORZ else: SB_VERT)
    var info = SCROLLINFO(cbSize: UINT(sizeof(SCROLLINFO)), fMask: SIF_ALL)
    if GetScrollInfo(hwnd, bar, addr info) != 0:
      var position = info.nPos
      case lowWord(wp)
      of SB_LINEUP: position -= 16
      of SB_LINEDOWN: position += 16
      of SB_PAGEUP: position -= int32(info.nPage)
      of SB_PAGEDOWN: position += int32(info.nPage)
      of SB_THUMBTRACK: position = info.nTrackPos
      of SB_TOP: position = info.nMin
      of SB_BOTTOM: position = info.nMax
      else: discard
      info.fMask = SIF_POS
      info.nPos = position
      discard SetScrollInfo(hwnd, bar, addr info, 1)
      discard InvalidateRect(hwnd, nil, 0)
    return 0
  DefWindowProcW(hwnd, msg, wp, lp)

proc addDescriptorNode(item: VextResourceDescriptor,
    parent: HTREEITEM, rootLabel = ""): HTREEITEM =
  var label = if rootLabel.len > 0: rootLabel
    elif item.path.len == 0: item.typeId
    else: item.path.split('/')[^1]
  if item.failureMessage.len > 0 and failureImageIndex < 0:
    label = "[!] " & label
  let labelWide = w(label)
  let binding = TreeBinding(descriptor: item)
  bindings.add binding
  var insert = TVINSERTSTRUCTW(hParent: parent, hInsertAfter: TVI_LAST,
    item: TVITEMW(mask: TVIF_TEXT or TVIF_PARAM or TVIF_IMAGE or
      TVIF_SELECTEDIMAGE, pszText: labelWide,
      iImage: if item.failureMessage.len > 0: failureImageIndex else: I_IMAGENONE,
      iSelectedImage: if item.failureMessage.len > 0:
        failureImageIndex else: I_IMAGENONE, lParam: cast[LPARAM](binding)))
  result = cast[HTREEITEM](SendMessageW(treeView, TVM_INSERTITEMW, 0,
    cast[LPARAM](addr insert)))
  if vrcEnumerateChildren in item.capabilities:
    let placeholder = TreeBinding(placeholder: true)
    bindings.add placeholder
    let placeholderLabel = w("Loading…")
    var placeholderInsert = TVINSERTSTRUCTW(hParent: result,
      hInsertAfter: TVI_LAST, item: TVITEMW(mask: TVIF_TEXT or TVIF_PARAM or
      TVIF_IMAGE or TVIF_SELECTEDIMAGE, pszText: placeholderLabel,
      iImage: I_IMAGENONE, iSelectedImage: I_IMAGENONE,
      lParam: cast[LPARAM](placeholder)))
    discard SendMessageW(treeView, TVM_INSERTITEMW, 0,
      cast[LPARAM](addr placeholderInsert))

proc addLoadedNode(node: VextResourceNode, parent: HTREEITEM): HTREEITEM =
  var label = if node.path.len == 0: node.typeId else: node.path.split('/')[^1]
  if node.failureMessage.len > 0 and failureImageIndex < 0:
    label = "[!] " & label
  let labelWide = w(label)
  let binding = TreeBinding(node: node, childrenLoaded: node.children.len == 0)
  bindings.add binding
  var insert = TVINSERTSTRUCTW(hParent: parent, hInsertAfter: TVI_LAST,
    item: TVITEMW(mask: TVIF_TEXT or TVIF_PARAM or TVIF_IMAGE or
      TVIF_SELECTEDIMAGE, pszText: labelWide,
      iImage: if node.failureMessage.len > 0: failureImageIndex else: I_IMAGENONE,
      iSelectedImage: if node.failureMessage.len > 0:
        failureImageIndex else: I_IMAGENONE, lParam: cast[LPARAM](binding)))
  result = cast[HTREEITEM](SendMessageW(treeView, TVM_INSERTITEMW, 0,
    cast[LPARAM](addr insert)))
  if node.children.len > 0:
    let placeholder = TreeBinding(placeholder: true)
    bindings.add placeholder
    let placeholderLabel = w("Loading…")
    var placeholderInsert = TVINSERTSTRUCTW(hParent: result,
      hInsertAfter: TVI_LAST, item: TVITEMW(mask: TVIF_TEXT or TVIF_PARAM or
      TVIF_IMAGE or TVIF_SELECTEDIMAGE, pszText: placeholderLabel,
      iImage: I_IMAGENONE, iSelectedImage: I_IMAGENONE,
      lParam: cast[LPARAM](placeholder)))
    discard SendMessageW(treeView, TVM_INSERTITEMW, 0,
      cast[LPARAM](addr placeholderInsert))

proc ensureLoadingPlaceholder(parent: HTREEITEM) =
  ## A descriptor created with enumerable children already owns either its
  ## original placeholder or materialized TreeView children. Derived children
  ## discovered only after loading need one placeholder, never one per visit.
  if parent == nil: return
  let firstChild = cast[HTREEITEM](SendMessageW(treeView, TVM_GETNEXTITEM,
    TVGN_CHILD, cast[LPARAM](parent)))
  if firstChild != nil: return
  let placeholder = TreeBinding(placeholder: true)
  bindings.add placeholder
  let placeholderLabel = w("Loading…")
  var placeholderInsert = TVINSERTSTRUCTW(hParent: parent,
    hInsertAfter: TVI_LAST, item: TVITEMW(mask: TVIF_TEXT or TVIF_PARAM or
    TVIF_IMAGE or TVIF_SELECTEDIMAGE, pszText: placeholderLabel,
    iImage: I_IMAGENONE, iSelectedImage: I_IMAGENONE,
    lParam: cast[LPARAM](placeholder)))
  discard SendMessageW(treeView, TVM_INSERTITEMW, 0,
    cast[LPARAM](addr placeholderInsert))

proc showTreeItemFailure(item: HTREEITEM) =
  if item == nil or failureImageIndex < 0: return
  var treeItem = TVITEMW(mask: TVIF_IMAGE or TVIF_SELECTEDIMAGE,
    hItem: item, iImage: failureImageIndex,
    iSelectedImage: failureImageIndex)
  discard SendMessageW(treeView, TVM_SETITEMW, 0,
    cast[LPARAM](addr treeItem))

proc rebuildTree() =
  discard SendMessageW(treeView, TVM_DELETEITEM, 0, cast[LPARAM](TVI_ROOT))
  bindings.setLen(0)
  firstPreviewItem = nil
  let roots = currentSession.rootDescriptors
  let filename = if currentFilename.len > 0:
      currentFilename.extractFilename
    else: currentSession.filename.extractFilename
  if roots.len == 1 and roots[0].kind == vrnkGroup:
    # Structural container roots already represent the opened file. Reusing
    # one avoids an unhelpful `archive -> archive -> members` hierarchy.
    discard addDescriptorNode(roots[0], TVI_ROOT, filename)
  else:
    # Legacy decoders may expose one or more payload roots directly. Give the
    # physical file its own stable tree node rather than applying its filename
    # as the label of every payload resource.
    let binding = TreeBinding(childrenLoaded: true,
      metadataText: "File: " & filename & "\r\nFormat: " &
        currentSession.selectedFormat.typeId & "\r\n")
    bindings.add binding
    let wide = w(filename)
    var insert = TVINSERTSTRUCTW(hParent: TVI_ROOT, hInsertAfter: TVI_LAST,
      item: TVITEMW(mask: TVIF_TEXT or TVIF_PARAM or TVIF_IMAGE or
        TVIF_SELECTEDIMAGE, pszText: wide, iImage: I_IMAGENONE,
        iSelectedImage: I_IMAGENONE, lParam: cast[LPARAM](binding)))
    let fileItem = cast[HTREEITEM](SendMessageW(treeView, TVM_INSERTITEMW, 0,
      cast[LPARAM](addr insert)))
    for root in roots:
      discard addDescriptorNode(root, fileItem)
    discard SendMessageW(treeView, TVM_EXPAND, TVE_EXPAND,
      cast[LPARAM](fileItem))

proc isPlayable(binding: TreeBinding): bool =
  if binding.isNil or binding.metadataText.len > 0 or binding.node.isNil:
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

proc trackerNoteText(cell: VextTrackerCell): string =
  case cell.noteKind
  of vtnkNone: "..."
  of vtnkRelease: "OFF"
  of vtnkCut: "CUT"
  of vtnkTrigger, vtnkTarget:
    const names = ["C-", "C#", "D-", "D#", "E-", "F-",
      "F#", "G-", "G#", "A-", "A#", "B-"]
    let prefix = if cell.noteKind == vtnkTarget: "~" else: ""
    prefix & names[cell.note mod 12] & $(cell.note div 12 - 1)

proc trackerCellText(cell: VextTrackerCell): string =
  # Tracker instruments are normalized to zero-based archetype indices, while
  # tracker UIs conventionally show their one-based source numbers.
  let instrument =
    if cell.hasInstrument: (cell.instrument + 1).toHex(2) else: ".."
  var command = "..."
  if cell.effects.len > 0:
    command = cell.effects[0].rawCommand.toHex(1) &
      cell.effects[0].rawParameter.toHex(2)
  cell.trackerNoteText.alignLeft(4) & " " & instrument & " " & command

proc trackerDetails(module: VextTrackerModule): string =
  result = "Tracker: " & module.title & "\r\n" &
    &"Channels: {module.channels.len}  Instruments: {module.instruments.len}  " &
    &"Patterns: {module.patterns.len}  Orders: {module.orders.len}\r\n" &
    &"Initial speed: {module.initialSpeed}  Tempo: {module.initialTempoBpm:g}  " &
    &"Rows/beat: {module.rowsPerBeat}\r\nOrders: "
  for index, patternIndex in module.orders:
    if index > 0: result.add " "
    result.add patternIndex.toHex(2)
  result.add "\r\n"
  if module.orders.len == 0: return
  let patternIndex = module.orders[0]
  if patternIndex < 0 or patternIndex >= module.patterns.len: return
  let pattern = module.patterns[patternIndex]
  result.add "\r\nFirst order position — pattern " &
    pattern.sourceIndex.toHex(2) & "\r\nROW"
  for channel in 0 ..< module.channels.len:
    result.add " | CH" & ($(channel + 1)).align(2) & "       "
  result.add "\r\n"
  for rowIndex, row in pattern.rows:
    result.add rowIndex.toHex(2)
    for cell in row.cells:
      result.add " | " & cell.trackerCellText
    result.add "\r\n"

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
  resetPreviewScrollPosition()
  selected = binding
  metadataViewBinding = nil
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
  elif binding.loadPending:
    currentView = vkText
    discard SetWindowTextW(textView,
      w("This resource is queued for background loading."))
  elif binding.node.isNil:
    currentView = vkText
    discard SetWindowTextW(textView, w(metadataString(binding.descriptor)))
  elif binding.node.failureMessage.len > 0:
    currentView = vkText
    discard SetWindowTextW(textView, w(failureString(binding.node)))
  elif binding.node.kind == vrnkText:
    currentView = vkText
    discard SetWindowTextW(textView, w(binding.node.text))
  elif binding.node.kind == vrnkTracker:
    currentView = vkText
    discard SetWindowTextW(textView, w(trackerDetails(binding.node.tracker)))
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
  if not binding.isNil and binding.metadataText.len == 0 and
      not binding.node.isNil:
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

proc releaseLoadedBindings(keep: TreeBinding = nil) =
  for binding in bindings:
    if binding != keep and not binding.isNil:
      binding.node = nil
      binding.loadedTree.roots.setLen(0)
      binding.loadedData.setLen(0)

proc sessionWorker(job: SessionJob) {.thread.} =
  var completed = SessionResult(kind: job.kind, binding: job.binding,
    item: job.item)
  try:
    {.cast(gcsafe).}:
      let progress: VextSessionProgressCallback =
        proc(event: VextSessionProgressEvent): bool =
          var position = 0
          if event.discovered > 0 and event.totalState == vptsFinal and
              (event.discovered > 1 or event.completed > 0):
            position = min(100, event.completed * 100 div event.discovered) + 1
          discard PostMessageW(mainWindow, WM_SESSION_PROGRESS,
            WPARAM(position), 0)
          true
      case job.kind
      of sjkExpand:
        completed.delta = job.session.expandResource(
          job.binding.descriptor.id, progress)
      of sjkLoad:
        completed.loaded = job.session.loadResource(
          job.binding.descriptor.id,
          progress = progress,
          maximumWorkingBytes = job.maximumWorkingBytes)
      of sjkDecodeLoaded:
        completed.decodeResult = decodeResourceOnDemand(job.binding.node)
  except CatchableError as error:
    completed.error = error.msg
  job.result[] = completed
  discard PostMessageW(mainWindow, WM_SESSION_DONE, 0,
    cast[LPARAM](job.result))

proc launchSessionJob(kind: SessionJobKind, binding: TreeBinding,
    item: HTREEITEM, maximumWorkingBytes: int) =
  sessionJobActive = true
  discard EnableWindow(openButton, 0)
  discard ShowWindow(progressBar, SW_SHOW)
  discard SendMessageW(progressBar, PBM_SETPOS, 0, 0)
  discard SendMessageW(progressBar, PBM_SETMARQUEE, 1, 30)
  let completed = cast[ptr SessionResult](allocShared0(sizeof(SessionResult)))
  createThread(sessionThread, sessionWorker,
    (kind, currentSession, binding, item, maximumWorkingBytes, completed))

proc startSessionJob(kind: SessionJobKind, binding: TreeBinding,
    item: HTREEITEM = nil, maximumWorkingBytes = 0): bool =
  if sessionJobActive:
    sessionQueue.add PendingSessionJob(kind: kind, binding: binding,
      item: item, maximumWorkingBytes: maximumWorkingBytes)
  else:
    launchSessionJob(kind, binding, item, maximumWorkingBytes)
  true

proc startLoadBinding(binding: TreeBinding, item: HTREEITEM): bool =
  if binding.isNil or binding.placeholder or binding.metadataText.len > 0:
    return false
  if binding.loadPending:
    return true
  if not binding.node.isNil:
    if binding.node.kind == vrnkOpaque and
        not binding.node.lazyPayload.source.isNil and
        not binding.node.nestedInspectionAttempted:
      result = startSessionJob(sjkDecodeLoaded, binding, item)
      if result:
        binding.loadPending = true
        selectBinding(binding)
      return
    return false
  if binding.descriptor.kind == vrnkGroup:
    return false
  var overrideLimit = 0
  let limit = currentSession.limits.maximumWorkingBytes
  if binding.descriptor.estimatedBytes > limit and
      not binding.workingLimitApproved:
    let message = "This resource is estimated to require " &
      byteSize(binding.descriptor.estimatedBytes) &
      ", above the per-resource working-data limit of " & byteSize(limit) &
      ".\n\nLoad this member anyway? Other archive members will remain unloaded."
    if MessageBoxW(mainWindow, w(message), w("Vexter working-data limit"),
        0x34) != 6:
      return true
    binding.workingLimitApproved = true
  if binding.workingLimitApproved:
    overrideLimit = binding.descriptor.estimatedBytes
  result = startSessionJob(sjkLoad, binding, item,
    maximumWorkingBytes = overrideLimit)
  if result:
    binding.loadPending = true
    selectBinding(binding)

proc startExpandBinding(binding: TreeBinding, item: HTREEITEM): bool =
  if binding.isNil or binding.placeholder or binding.childrenLoaded:
    return false
  if not binding.node.isNil and binding.node.children.len > 0:
    let placeholder = cast[HTREEITEM](SendMessageW(treeView, TVM_GETNEXTITEM,
      TVGN_CHILD, cast[LPARAM](item)))
    if placeholder != nil:
      discard SendMessageW(treeView, TVM_DELETEITEM, 0,
        cast[LPARAM](placeholder))
    for child in binding.node.children:
      discard addLoadedNode(child, item)
    binding.childrenLoaded = true
    return true
  if vrcEnumerateChildren notin binding.descriptor.capabilities:
    return false
  startSessionJob(sjkExpand, binding, item)

proc finishSessionJob(result: ptr SessionResult) =
  joinThread(sessionThread)
  let completed = result[]
  reset(result[])
  deallocShared(result)
  sessionJobActive = false
  if completed.kind in {sjkLoad, sjkDecodeLoaded} and
      not completed.binding.isNil:
    completed.binding.loadPending = false
  if completed.error.len > 0:
    if completed.kind in {sjkLoad, sjkDecodeLoaded}:
      completed.binding.metadataText =
        "Could not load this resource.\r\n\r\n" & completed.error
      if selected == completed.binding:
        selectBinding(completed.binding)
    else:
      showError(completed.error)
  else:
    case completed.kind
    of sjkExpand:
      let firstChild = cast[HTREEITEM](SendMessageW(treeView, TVM_GETNEXTITEM,
        TVGN_CHILD, cast[LPARAM](completed.item)))
      if firstChild != nil:
        discard SendMessageW(treeView, TVM_DELETEITEM, 0,
          cast[LPARAM](firstChild))
      for child in completed.delta.children:
        discard addDescriptorNode(child, completed.item)
      completed.binding.childrenLoaded = true
    of sjkLoad:
      completed.binding.releaseLoadedBindings()
      completed.binding.loadedData = completed.loaded.data
      completed.binding.loadedTree = completed.loaded.resources
      if completed.binding.loadedTree.roots.len == 1:
        completed.binding.node = completed.binding.loadedTree.roots[0]
      elif completed.binding.loadedTree.roots.len > 1:
        completed.binding.node = VextResourceNode(
          path: completed.binding.descriptor.path,
          typeId: completed.loaded.descriptor.typeId, kind: vrnkGroup,
          children: completed.binding.loadedTree.roots)
      if not completed.binding.node.isNil and
          completed.binding.node.failureMessage.len > 0:
        showTreeItemFailure(completed.item)
      if not completed.binding.node.isNil and
          completed.binding.node.children.len > 0:
        if vrcEnumerateChildren notin completed.binding.descriptor.capabilities:
          completed.binding.childrenLoaded = false
          ensureLoadingPlaceholder(completed.item)
      if selected == completed.binding:
        selectBinding(completed.binding)
    of sjkDecodeLoaded:
      if completed.decodeResult == vddDecoded and
          completed.binding.node.children.len == 1:
        completed.binding.node = completed.binding.node.children[0]
      if completed.decodeResult == vddDecoded and
          completed.binding.node.kind == vrnkGroup and
          completed.binding.node.children.len > 0:
        completed.binding.childrenLoaded = false
        ensureLoadingPlaceholder(completed.item)
      if completed.decodeResult == vddFailed:
        showTreeItemFailure(completed.item)
      if selected == completed.binding:
        selectBinding(completed.binding)
  if sessionQueue.len > 0:
    let pending = sessionQueue[0]
    sessionQueue.delete(0)
    launchSessionJob(pending.kind, pending.binding, pending.item,
      pending.maximumWorkingBytes)
  else:
    discard SendMessageW(progressBar, PBM_SETMARQUEE, 0, 0)
    discard ShowWindow(progressBar, 0)
    discard EnableWindow(openButton, 1)

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
        if waveOutWrite(waveHandle, addr waveHeader, UINT(sizeof(WAVEHDR))) == 0:
          audioPlaying = true
          discard SetWindowTextW(playButton, w("Pause"))
          discard SetTimer(mainWindow, 2, 50, nil)
        else:
          stopAudio()
      else:
        stopAudio()

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

proc chooseFolder(): string =
  var displayName = newWideCString("", 32768)
  var info = BROWSEINFOW(hwndOwner: mainWindow,
    pszDisplayName: displayName,
    lpszTitle: w("Choose a directory for the extracted files"),
    ulFlags: BIF_RETURNONLYFSDIRS or BIF_NEWDIALOGSTYLE)
  let item = SHBrowseForFolderW(addr info)
  if item == nil: return
  defer: CoTaskMemFree(item)
  var path = newWideCString("", 32768)
  if SHGetPathFromIDListW(item, path) != 0:
    result = $path

proc canExtractCurrentSession(): bool =
  if currentSession.isNil: return false
  for descriptor in currentSession.rootDescriptors:
    if vrcExtractTree in descriptor.capabilities:
      return true

proc directoryHasEntries(path: string): bool =
  if not path.dirExists: return false
  for _ in walkDir(path):
    return true

proc writeByteFile(path: string, data: openArray[byte]) =
  var contents = newString(data.len)
  for index, value in data:
    contents[index] = char(value)
  writeFile(path, contents)

proc extractionWorker(job: ExtractionJob) {.thread.} =
  var completed: ExtractionResult
  try:
    {.cast(gcsafe).}:
      let plan = job.session.extractionPlan()
      completed.warnings = plan.warnings
      for entry in plan.entries:
        let destination = job.destination / entry.relativePath
        if symlinkExists(destination):
          raise newException(IOError,
            "extraction destination is a symbolic link: " & destination)
        case entry.kind
        of veekDirectory:
          if destination.fileExists:
            raise newException(IOError,
              "cannot create directory over an existing file: " & destination)
        of veekFile:
          if destination.dirExists:
            raise newException(IOError,
              "cannot extract file over an existing directory: " & destination)
          if destination.fileExists and not job.overwrite:
            raise newException(IOError,
              "output file already exists: " & destination)
          var parent = destination.parentDir
          while parent.len > 0 and parent != job.destination:
            if symlinkExists(parent):
              raise newException(IOError,
                "an extraction parent is a symbolic link: " & parent)
            if parent.fileExists:
              raise newException(IOError,
                "a parent path is an existing file: " & parent)
            let next = parent.parentDir
            if next == parent: break
            parent = next
      createDir(job.destination)
      for entry in plan.entries:
        let destination = job.destination / entry.relativePath
        case entry.kind
        of veekDirectory:
          createDir(destination)
        of veekFile:
          createDir(destination.parentDir)
          destination.writeByteFile(
            job.session.materializePayload(entry.descriptor.id,
              maximumWorkingBytes = max(
                job.session.limits.maximumWorkingBytes,
                entry.descriptor.estimatedBytes)))
          inc completed.files
  except CatchableError as error:
    completed.error = error.msg
  job.result[] = completed
  discard PostMessageW(mainWindow, WM_EXTRACTION_DONE, 0,
    cast[LPARAM](job.result))

proc startExtraction() =
  if extractionActive or sessionJobActive or not canExtractCurrentSession():
    return
  let destination = chooseFolder()
  if destination.len == 0: return
  var overwrite = false
  if directoryHasEntries(destination):
    let message = "The selected directory is not empty. Existing files with " &
      "the same names will be replaced; unrelated files will be left alone.\n\nContinue?"
    if MessageBoxW(mainWindow, w(message), w("Extract archive"), 0x34) != 6:
      return
    overwrite = true
  extractionActive = true
  discard EnableWindow(openButton, 0)
  discard EnableWindow(extractButton, 0)
  discard EnableWindow(exportButton, 0)
  discard EnableWindow(treeView, 0)
  discard ShowWindow(progressBar, SW_SHOW)
  discard SendMessageW(progressBar, PBM_SETMARQUEE, 1, 30)
  let completed = cast[ptr ExtractionResult](
    allocShared0(sizeof(ExtractionResult)))
  createThread(extractionThread, extractionWorker,
    (currentSession, destination, overwrite, completed))

proc finishExtraction(result: ptr ExtractionResult) =
  joinThread(extractionThread)
  let completed = result[]
  reset(result[])
  deallocShared(result)
  extractionActive = false
  discard SendMessageW(progressBar, PBM_SETMARQUEE, 0, 0)
  discard ShowWindow(progressBar, 0)
  discard EnableWindow(openButton, 1)
  discard EnableWindow(treeView, 1)
  discard EnableWindow(extractButton,
    if canExtractCurrentSession(): 1 else: 0)
  discard EnableWindow(exportButton,
    if not selected.isNil and not selected.node.isNil and
        selected.metadataText.len == 0 and
        selected.node.exportFormatsFor.len > 0: 1 else: 0)
  if completed.error.len > 0:
    showError(completed.error)
  else:
    var message = &"Extracted {completed.files} file(s)."
    if completed.warnings.len > 0:
      message.add "\n\nWarnings:\n"
      for warning in completed.warnings:
        message.add "- " & warning & "\n"
    discard MessageBoxW(mainWindow, w(message), w("Vexter"),
      if completed.warnings.len > 0: 0x30 else: 0x40)

proc guiFileSource(path: string): VextByteSource =
  let length = int(path.getFileSize)
  var input = open(path, fmRead)
  newByteSource(length,
    proc(offset, amount: int): seq[byte] =
      input.setFilePos(offset)
      result = newSeq[byte](amount)
      if amount > 0 and input.readBuffer(addr result[0], amount) != amount:
        raise newException(IOError, "short read from " & path),
    path, proc() = input.close())

proc guiCompanionResolver(path: string): VextCompanionSourceResolver =
  let directory = path.parentDir
  result = proc(relativePath: string): VextByteSource =
    let companionPath = directory / relativePath
    if companionPath.fileExists: guiFileSource(companionPath) else: nil

proc loadWorker(job: LoadJob) {.thread.} =
  var loaded = LoadResult(filename: job.filename)
  try:
    {.cast(gcsafe).}:
      loaded.session = openInspectionSession(job.filename,
        newSourceCollection(guiFileSource(job.filename),
          guiCompanionResolver(job.filename)))
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
    if not currentSession.isNil: currentSession.close()
    selected = nil
    currentFilename = loaded.filename
    currentSession = loaded.session
    rebuildTree()
    discard EnableWindow(extractButton,
      if canExtractCurrentSession(): 1 else: 0)
    discard SetWindowTextW(mainWindow, w("Vexter - " & loaded.filename.extractFilename))

proc doExport() =
  if selected.isNil or selected.metadataText.len > 0: return
  let formats = selected.node.exportFormatsFor
  let index = int(SendMessageW(formatCombo, CB_GETCURSEL, 0, 0))
  if index < 0 or index >= formats.len: return
  let format = formats[index]
  if format.id == "gpl" and selected.node.gplExportUsesAlpha:
    let message = "This palette contains transparency. Vexter will use " &
      "Aseprite's RGBA extension to the GIMP Palette format. GIMP may " &
      "ignore the alpha values when opening this file.\n\nContinue?"
    if MessageBoxW(mainWindow, w(message), w("GPL alpha compatibility"),
        0x34) != 6:
      return
  let destination = chooseFile(true, format.extensions[0],
    format.displayName & "\0*." & format.extensions[0] & "\0All files\0*.*\0\0")
  if destination.len == 0: return
  try:
    var allowLarge = false
    var exported: VextExportResult
    while true:
      try:
        exported = exportResource(selected.loadedTree,
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
  discard MoveWindow(extractButton, 82, 5, 78, 24, 1)
  discard MoveWindow(progressBar, 168, 8, 136, 18, 1)
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
    extractButton = CreateWindowExW(0, w("BUTTON"), w("Extract..."),
      WS_CHILD or WS_VISIBLE, 0, 0, 0, 0, hwnd,
      cast[HMENU](1014), instance, nil)
    treeView = CreateWindowExW(0, w("SysTreeView32"), w(""), WS_CHILD or WS_VISIBLE or
      WS_BORDER or TVS_HASBUTTONS or TVS_HASLINES or TVS_LINESATROOT or
      TVS_SHOWSELALWAYS,
      0, 0, 0, 0, hwnd, cast[HMENU](1002), instance, nil)
    treeImages = ImageList_Create(16, 16, ILC_COLOR32 or ILC_MASK, 1, 1)
    if treeImages != nil:
      let warningIcon = LoadIconW(nil, IDI_WARNING)
      if warningIcon != nil:
        failureImageIndex = ImageList_ReplaceIcon(treeImages, -1, warningIcon)
      if failureImageIndex >= 0:
        discard SendMessageW(treeView, TVM_SETIMAGELIST, TVSIL_NORMAL,
          cast[LPARAM](treeImages))
    preview = CreateWindowExW(0, w("VexterPreview"), w(""), WS_CHILD or WS_VISIBLE or WS_BORDER or
      WS_HSCROLL or WS_VSCROLL,
      0, 0, 0, 0, hwnd, cast[HMENU](1003), instance, nil)
    discard ShowScrollBar(preview, SB_BOTH, 0)
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
    # Explicit fonts avoid the legacy stock control font. Keep ordinary UI
    # chrome proportional and textual resources fixed-width for listings,
    # tracker columns, hexadecimal diagnostics, and Unicode block characters.
    uiFont = CreateFontW(-12, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 0, 0,
      w("Segoe UI"))
    textFont = CreateFontW(-13, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 0, 1,
      w("Consolas"))
    for control in [openButton, extractButton, treeView, fontModeCombo, fontSample,
        fontGlyphCombo, scaleCombo, playButton, formatCombo, exportButton]:
      control.setControlFont(uiFont)
    for control in [textView, fontDetails]:
      control.setControlFont(textFont)
    discard EnableWindow(playButton, 0)
    discard EnableWindow(exportButton, 0)
    discard EnableWindow(extractButton, 0)
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
        resetPreviewScrollPosition()
        discard InvalidateRect(preview, nil, 1)
    of 1006: togglePlayback()
    of 1008: doExport()
    of 1014: startExtraction()
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
      let binding = cast[TreeBinding](notification.itemNew.lParam)
      if not startLoadBinding(binding, notification.itemNew.hItem):
        selectBinding(binding)
    elif notification != nil and notification.hdr.hwndFrom == treeView and
        notification.hdr.code == TVN_ITEMEXPANDINGW:
      let binding = cast[TreeBinding](notification.itemNew.lParam)
      discard startExpandBinding(binding, notification.itemNew.hItem)
    elif notification != nil and notification.hdr.hwndFrom == treeView and
        notification.hdr.code == NM_RCLICK:
      showTreeMetadataMenu()
    return 0
  of WM_TIMER:
    if wp == 2:
      if audioPlaying and (waveHeader.dwFlags and WHDR_DONE) != 0:
        stopAudio()
      return 0
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
  of WM_SESSION_DONE:
    finishSessionJob(cast[ptr SessionResult](lp))
    return 0
  of WM_SESSION_PROGRESS:
    if sessionJobActive:
      if wp == 0:
        discard SendMessageW(progressBar, PBM_SETMARQUEE, 1, 30)
      else:
        discard SendMessageW(progressBar, PBM_SETMARQUEE, 0, 0)
        discard SendMessageW(progressBar, PBM_SETPOS, wp - 1, 0)
    return 0
  of WM_EXTRACTION_DONE:
    finishExtraction(cast[ptr ExtractionResult](lp))
    return 0
  of WM_CLOSE:
    if extractionActive:
      showError("Extraction is still in progress. Wait for it to finish before closing Vexter.")
      return 0
    stopAudio()
  of WM_DESTROY:
    if not currentSession.isNil: currentSession.close()
    if treeImages != nil:
      discard SendMessageW(treeView, TVM_SETIMAGELIST, TVSIL_NORMAL, 0)
      discard ImageList_Destroy(treeImages)
      treeImages = nil
    if textFont != nil:
      discard DeleteObject(textFont)
      textFont = nil
    if uiFont != nil:
      discard DeleteObject(uiFont)
      uiFont = nil
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
