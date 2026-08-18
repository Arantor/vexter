## Diagnostic source-text decoding for tokenised AMOS listings.

import std/[math, strutils]
import ./amos_listing_tokens

proc requireBytes(data: openArray[byte], offset, count: int) =
  if offset < 0 or count < 0 or offset > data.len - count:
    raise newException(ValueError, "truncated AMOS listing token")

proc word(data: openArray[byte], offset: int): int =
  data.requireBytes(offset, 2)
  (int(data[offset]) shl 8) or int(data[offset + 1])

proc dword(data: openArray[byte], offset: int): uint32 =
  data.requireBytes(offset, 4)
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc text(data: openArray[byte], offset, count: int): string =
  data.requireBytes(offset, count)
  result = newString(count)
  for index in 0 ..< count:
    result[index] = char(data[offset + index])
  while result.len > 0 and result[^1] == '\0':
    result.setLen(result.len - 1)

proc hex(data: openArray[byte], offset, count: int): string =
  const digits = "0123456789abcdef"
  data.requireBytes(offset, count)
  for index in offset ..< offset + count:
    result.add digits[int(data[index] shr 4)]
    result.add digits[int(data[index] and 0x0f)]

proc paddedLength(length: int): int =
  length + (length and 1)

proc binaryLiteral(value: uint32): string =
  result = toBin(BiggestInt(value), 32).strip(
    leading = true, trailing = false, chars = {'0'})
  if result.len == 0: result = "0"

proc hexLiteral(value: uint32): string =
  result = toHex(BiggestInt(value), 8).strip(
    leading = true, trailing = false, chars = {'0'})
  if result.len == 0: result = "0"

proc decryptAmosProcedures*(listing: var seq[byte]) =
  ## Decrypts protected procedure line payloads in place. Line length,
  ## indentation, and the first token remain cleartext in the stored form.
  var offset = 0
  while offset < listing.len:
    listing.requireBytes(offset, 2)
    let lineBytes = int(listing[offset]) * 2
    if lineBytes < 2 or offset > listing.len - lineBytes:
      raise newException(ValueError, "invalid AMOS listing line length")
    var decryptedEnd = -1
    if lineBytes >= 14 and listing.word(offset + 2) == 0x0376:
      let flags = listing[offset + 10]
      if (flags and 0x20) != 0 and (flags and 0x10) == 0:
        let size = int(listing.dword(offset + 4))
        let endLine = offset + size + 14
        var line = offset + lineBytes
        if size < 0 or line > endLine or endLine >= listing.len:
          raise newException(ValueError,
            "invalid encrypted AMOS procedure boundary")
        var key = (uint32(size) shl 8) or uint32(listing[offset + 11])
        var key2 = 1'u32
        let key3 = uint32(listing.word(offset + 8))
        while line < endLine:
          listing.requireBytes(line, 2)
          let next = line + int(listing[line]) * 2
          if next <= line or next > listing.len or (next - line) mod 2 != 0:
            raise newException(ValueError,
              "invalid encrypted AMOS procedure line")
          var position = line + 4
          while position < next:
            listing[position] = listing[position] xor byte(key shr 8)
            listing[position + 1] = listing[position + 1] xor byte(key)
            position += 2
            key = (key and 0xffff0000'u32) or
              ((key + key2) and 0xffff'u32)
            key2 = (key2 + key3) and 0xffff'u32
            key = (key shr 1) or (key shl 31)
          line = next
        listing[offset + 10] = listing[offset + 10] xor 0x20
        decryptedEnd = line
    if decryptedEnd >= 0:
      offset = decryptedEnd
    else:
      offset += lineBytes

proc decodeAmosLine*(line: openArray[byte]): string =
  var position = 0
  while position < line.len:
    line.requireBytes(position, 2)
    let token = line.word(position)
    if token == 0:
      return
    let simple = amosSimpleToken(token)
    if simple.len > 0:
      result.add simple
      position += 2
      continue

    case token
    of 0x0006, 0x000c, 0x0012, 0x0018:
      line.requireBytes(position, 6)
      var nameLength = int(line[position + 4])
      let flags = int(line[position + 5])
      if token != 0x0006:
        nameLength = nameLength.paddedLength
      result.add line.text(position + 6, nameLength).toUpperAscii
      if token == 0x000c:
        result.add ':'
      elif token in [0x0006, 0x0012]:
        if flags == 1: result.add '#'
        elif flags == 2: result.add '$'
      position += 6 + nameLength
    of 0x001e:
      result.add '%' & binaryLiteral(line.dword(position + 2))
      position += 6
    of 0x0026, 0x002e:
      let rawLength = line.word(position + 2)
      let storedLength = rawLength.paddedLength
      let delimiter = if token == 0x0026: '"' else: '\''
      result.add delimiter
      result.add line.text(position + 4, storedLength)
      result.add delimiter
      position += 4 + storedLength
    of 0x0036:
      result.add '$' & hexLiteral(line.dword(position + 2))
      position += 6
    of 0x003e:
      result.add $line.dword(position + 2)
      position += 6
    of 0x0046:
      line.requireBytes(position, 6)
      let
        mantissa = (int(line[position + 2]) shl 16) or
          (int(line[position + 3]) shl 8) or int(line[position + 4])
        exponent = int(line[position + 5])
      var value = 0.0
      for bit in countdown(23, 0):
        if (mantissa and (1 shl bit)) != 0:
          value += pow(2.0, float(bit + exponent - 88))
      result.add $value
      position += 6
    of 0x027e, 0x023c, 0x0250, 0x0268, 0x02be, 0x02d0:
      let keyword = case token
        of 0x027e: "Do "
        of 0x023c: "For "
        of 0x0250: "Repeat "
        of 0x0268: "While "
        of 0x02be: "If "
        else: "Else "
      line.requireBytes(position, 4)
      result.add keyword
      position += 4
    of 0x0290:
      line.requireBytes(position, 6)
      result.add "Exit If "
      position += 6
    of 0x0376:
      line.requireBytes(position, 12)
      let bytesToEnd = int(line.dword(position + 2))
      let flags = line[position + 8]
      result.add "Proc "
      if (flags and 0x20) != 0:
        # TODO: encrypted procedure bodies require AMOS decryption semantics.
        result.add "[encrypted procedure]"
        return
      position += 12
      if bytesToEnd < 0: return
    of 0x0404:
      line.requireBytes(position, 4)
      result.add "Data "
      position += 4
    of 0x064a, 0x0652:
      line.requireBytes(position, 4)
      let commentLength = int(line[position + 3])
      result.add(if token == 0x0652: "'" else: "Rem")
      result.add line.text(position + 4, commentLength)
      return
    of 0x004e:
      line.requireBytes(position, 6)
      let
        extension = int(line[position + 2])
        extensionToken = line.word(position + 4)
        mapped = amosExtensionToken(extension, extensionToken)
      if mapped.len > 0:
        result.add mapped
      else:
        result.add "[ext " & $extension & " " &
          line.hex(position + 4, 2) & "]"
      position += 6
    else:
      result.add '[' & line.hex(position, line.len - position) & ']'
      return

proc decodeAmosListing*(data: openArray[byte]): string =
  var listing = @data
  decryptAmosProcedures(listing)
  var offset = 0
  while offset < listing.len:
    listing.requireBytes(offset, 2)
    let
      lineWords = int(listing[offset])
      indent = int(listing[offset + 1])
    if lineWords < 1:
      raise newException(ValueError, "invalid AMOS listing line length")
    let lineDataLength = (lineWords - 1) * 2
    listing.requireBytes(offset + 2, lineDataLength)
    if lineDataLength < 2 or listing[offset + lineDataLength] != 0 or
        listing[offset + lineDataLength + 1] != 0:
      raise newException(ValueError, "AMOS listing line at byte " & $offset &
        " is not null terminated")
    if indent > 1:
      result.add repeat(' ', indent - 1)
    result.add decodeAmosLine(listing.toOpenArray(
      offset + 2, offset + 1 + lineDataLength))
    result.add '\n'
    offset += lineDataLength + 2
