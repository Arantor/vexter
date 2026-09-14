## Documented Sierra SCI main-vocabulary decoding.
## Format facts are derived from the supplied SCI Specifications chapter 6;
## packed-ID byte order is confirmed by the supplied authentic SCI0 corpus.

import std/strutils

type
  SciVocabularyWord* = object
    text*: string
    classMask*, group*: int
  SciVocabulary* = object
    letterOffsets*: array[26, int]
    words*: seq[SciVocabularyWord]
  SciGrammarTerm* = object
    semantic*, symbol*: int
  SciGrammarRule* = object
    nonterminal*: int
    terms*: seq[SciGrammarTerm]
  SciGrammar* = object
    rules*: seq[SciGrammarRule]
  SciSuffixRule* = object
    suffix*, reduction*: string
    outputClass*, stemClass*: int
  SciStringRecord* = object
    data*: seq[byte]
  SciStringTable* = object
    records*: seq[SciStringRecord]

const SciVocabularyClasses* = [
  (bit: 0x001, name: "numbers"),
  (bit: 0x002, name: "special-002"),
  (bit: 0x004, name: "special-004"),
  (bit: 0x008, name: "special-008"),
  (bit: 0x010, name: "prepositions"),
  (bit: 0x020, name: "articles"),
  (bit: 0x040, name: "qualifying-adjectives"),
  (bit: 0x080, name: "relative-pronouns"),
  (bit: 0x100, name: "nouns"),
  (bit: 0x200, name: "indicative-verbs"),
  (bit: 0x400, name: "adverbs"),
  (bit: 0x800, name: "imperative-verbs")]

proc le16(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 2:
    raise newException(ValueError, "truncated SCI vocabulary offset")
  int(data[at]) or (int(data[at + 1]) shl 8)

proc be16(data: openArray[byte], at: int): int =
  if at < 0 or at > data.len - 2:
    raise newException(ValueError, "truncated SCI vocabulary word")
  (int(data[at]) shl 8) or int(data[at + 1])

proc terminatedString(data: openArray[byte], at: var int): string =
  while at < data.len and data[at] != 0:
    if data[at] < 0x20 or data[at] > 0x7e:
      raise newException(ValueError, "SCI vocabulary contains non-ASCII text")
    result.add char(data[at]); inc at
  if at >= data.len:
    raise newException(ValueError, "unterminated SCI vocabulary string")
  inc at

proc parseSciVocabulary*(data: openArray[byte]): SciVocabulary =
  if data.len < 56:
    raise newException(ValueError, "SCI main vocabulary is too short")
  for index in 0 ..< 26:
    result.letterOffsets[index] = le16(data, index * 2)
    if result.letterOffsets[index] != 0 and
        result.letterOffsets[index] notin 52 ..< data.len:
      raise newException(ValueError, "SCI vocabulary letter offset is outside the resource")

  var starts: seq[int]
  var previous = ""
  var at = 52
  while at < data.len:
    starts.add at
    let retained = int(data[at]); inc at
    if retained > previous.len:
      raise newException(ValueError, "SCI vocabulary prefix exceeds the previous word")
    var word = previous[0 ..< retained]
    var terminated = false
    while at < data.len:
      let value = data[at]; inc at
      let character = value and 0x7f
      if character < 0x20 or character > 0x7e:
        raise newException(ValueError, "SCI vocabulary word contains non-ASCII data")
      word.add char(character)
      if (value and 0x80) != 0:
        terminated = true
        break
    if not terminated or at > data.len - 3:
      raise newException(ValueError, "truncated SCI vocabulary word definition")
    let packed = (int(data[at]) shl 16) or (int(data[at + 1]) shl 8) or
      int(data[at + 2])
    at += 3
    result.words.add SciVocabularyWord(text: word,
      classMask: packed shr 12, group: packed and 0xfff)
    previous = word
  if result.words.len == 0:
    raise newException(ValueError, "SCI main vocabulary contains no words")
  for letter, offset in result.letterOffsets:
    if offset == 0: continue
    if offset notin starts:
      raise newException(ValueError, "SCI vocabulary letter offset is not a word boundary")
    let word = result.words[starts.find(offset)].text
    if word.len == 0 or word[0].toLowerAscii != char(ord('a') + letter):
      raise newException(ValueError, "SCI vocabulary letter offset points to the wrong letter")

proc completeListing*(vocabulary: SciVocabulary): string =
  result = "word\tclass-mask\tgroup\n"
  for word in vocabulary.words:
    result.add word.text & "\t0x" & word.classMask.toHex(3) & "\t0x" &
      word.group.toHex(3) & "\n"

proc classListing*(vocabulary: SciVocabulary, classBit: int): string =
  result = "word\tgroup\n"
  for word in vocabulary.words:
    if (word.classMask and classBit) != 0:
      result.add word.text & "\t0x" & word.group.toHex(3) & "\n"

proc classNames*(mask: int): string =
  var names: seq[string]
  for classInfo in SciVocabularyClasses:
    if (mask and classInfo.bit) != 0: names.add classInfo.name
  let unknown = mask and not 0xfff
  if unknown != 0: names.add "unknown-0x" & unknown.toHex(4)
  if names.len == 0: "none" else: names.join("|")

proc parseSciSuffixes*(data: openArray[byte]): seq[SciSuffixRule] =
  var at = 0
  while at < data.len:
    if data[at] == 0xff:
      while at < data.len:
        if data[at] != 0xff:
          raise newException(ValueError, "SCI suffix vocabulary has invalid padding")
        inc at
      break
    if data[at] == 0:
      inc at
      while at < data.len:
        if data[at] != 0xff:
          raise newException(ValueError,
            "SCI suffix vocabulary has invalid terminator padding")
        inc at
      break
    let suffix = terminatedString(data, at)
    let outputClass = be16(data, at); at += 2
    let reduction = terminatedString(data, at)
    let stemClass = be16(data, at); at += 2
    result.add SciSuffixRule(suffix: suffix, reduction: reduction,
      outputClass: outputClass, stemClass: stemClass)
  if result.len == 0:
    raise newException(ValueError, "SCI suffix vocabulary contains no rules")

proc suffixListing*(rules: openArray[SciSuffixRule]): string =
  result = "suffix\toutput-class\treduction\tallowed-stem-class\n"
  for rule in rules:
    result.add rule.suffix & "\t" & classNames(rule.outputClass) &
      " (0x" & rule.outputClass.toHex(4) & ")\t" & rule.reduction & "\t" &
      classNames(rule.stemClass) & " (0x" & rule.stemClass.toHex(4) & ")\n"

proc parseSciStringTable*(data: openArray[byte]): SciStringTable =
  if data.len < 4:
    raise newException(ValueError, "SCI string table is too short")
  let count = le16(data, 0)
  if count == 0 or 2 + count * 2 > data.len:
    raise newException(ValueError, "SCI string table has an invalid record count")
  for index in 0 ..< count:
    let offset = le16(data, 2 + index * 2)
    if offset < 2 + count * 2 or offset > data.len - 2:
      raise newException(ValueError, "SCI string table offset is outside the resource")
    let size = le16(data, offset)
    if size < 0 or offset + 2 + size > data.len:
      raise newException(ValueError, "SCI string table record is truncated")
    result.records.add SciStringRecord(data: @data[offset + 2 ..< offset + 2 + size])

proc printableSuffix(record: SciStringRecord): string =
  var at = 0
  while at < record.data.len and
      (record.data[at] < 0x20 or record.data[at] > 0x7e): inc at
  for index in at ..< record.data.len:
    let value = record.data[index]
    result.add(if value in 0x20'u8 .. 0x7e'u8: char(value) else: '?')

proc namedListing*(table: SciStringTable, valueName: string,
    prefixBytes = 0): string =
  result = "id\t" & valueName
  if prefixBytes > 0: result.add "\tformat-data"
  result.add "\n"
  for index, record in table.records:
    result.add $index & "\t" & record.printableSuffix
    if prefixBytes > 0:
      result.add "\t"
      for prefixAt in 0 ..< min(prefixBytes, record.data.len):
        if prefixAt > 0: result.add " "
        result.add record.data[prefixAt].toHex(2)
    result.add "\n"

proc helpListing*(table: SciStringTable): string =
  for index, record in table.records:
    if index > 0: result.add "\n\n"
    result.add "Section " & $(index + 1) & "\n\n"
    for value in record.data:
      if value == 0x1a: continue
      result.add(if value == 9 or value == 10 or value == 13 or
        value in 0x20'u8 .. 0x7e'u8: char(value) else: '?')

proc parseSciGrammar*(data: openArray[byte]): SciGrammar =
  if data.len == 0 or data.len mod 20 != 0:
    raise newException(ValueError,
      "SCI parser grammar must contain complete 20-byte rules")
  for at in countup(0, data.len - 20, 20):
    var rule = SciGrammarRule(nonterminal: le16(data, at))
    if rule.nonterminal == 0:
      for paddingAt in at ..< data.len:
        if data[paddingAt] != 0:
          raise newException(ValueError,
            "SCI parser grammar contains a malformed zero rule")
      break
    var wordAt = at + 2
    var terminated = false
    while wordAt < at + 20:
      let semantic = le16(data, wordAt)
      wordAt += 2
      if semantic == 0:
        terminated = true
        while wordAt < at + 20:
          if le16(data, wordAt) != 0:
            raise newException(ValueError,
              "SCI parser grammar has data after its tuple terminator")
          wordAt += 2
        break
      if wordAt >= at + 20:
        raise newException(ValueError,
          "SCI parser grammar has an incomplete semantic tuple")
      rule.terms.add SciGrammarTerm(
        semantic: semantic, symbol: le16(data, wordAt))
      wordAt += 2
    if not terminated:
      raise newException(ValueError,
        "SCI parser grammar rule has no tuple terminator")
    if rule.terms.len == 0:
      raise newException(ValueError, "SCI parser grammar contains an empty rule")
    result.rules.add rule

proc grammarSemanticName(semantic: int): string =
  case semantic
  of 0x141: "predicate"
  of 0x142: "subject"
  of 0x143: "suffix"
  of 0x144: "reference"
  of 0x146: "class"
  of 0x14d: "group"
  of 0x154: "force-storage"
  else: "semantic-0x" & semantic.toHex(3)

proc listing*(grammar: SciGrammar): string =
  result = "rule\tnonterminal\tproduction\n"
  for index, rule in grammar.rules:
    var production: seq[string]
    for term in rule.terms:
      production.add grammarSemanticName(term.semantic) & ":0x" &
        term.symbol.toHex(3)
    result.add $index & "\t0x" & rule.nonterminal.toHex(3) & "\t" &
      production.join(" ") & "\n"

proc annotatedListing*(grammar: SciGrammar,
    vocabulary: SciVocabulary): string =
  if grammar.rules.len > 0 and grammar.rules[0].terms.len > 0:
    result.add "start: <nt-" & grammar.rules[0].terms[0].symbol.toHex(3) & ">\n\n"
  for index in 1 ..< grammar.rules.len:
    let rule = grammar.rules[index]
    result.add "<nt-" & rule.nonterminal.toHex(3) & "> ::= "
    var terms: seq[string]
    for term in rule.terms:
      case term.semantic
      of 0x146:
        terms.add "class:" & classNames(term.symbol) & "[0x" &
          term.symbol.toHex(3) & "]"
      of 0x14d:
        var words: seq[string]
        for word in vocabulary.words:
          if word.group == term.symbol: words.add word.text
        terms.add "group:0x" & term.symbol.toHex(3) &
          (if words.len > 0: "[" & words.join("|") & "]" else: "")
      else:
        terms.add grammarSemanticName(term.semantic) & ":<nt-" &
          term.symbol.toHex(3) & ">"
    result.add terms.join(" ") & "\n"
