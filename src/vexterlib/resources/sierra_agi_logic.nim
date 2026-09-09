## Conservative Sierra AGI LOGIC bytecode disassembly, based on supplied chapter 6.
import std/strutils

type OperandKind = enum
  okNumber, okVariable, okFlag, okScreenObject, okInventoryObject,
  okController, okString, okWord, okMessage, okLogic, okRoom, okView, okSound

const
  testNames = "invalid,equaln,equalv,lessn,lessv,greatern,greaterv,isset,issetv,has,obj.in.room,posn,controller,have.key,said,compare.strings,obj.in.box,center.posn,right.posn"
  testCounts = [-2,2,2,2,2,2,2,1,1,1,2,5,1,0,-1,2,5,5,5]
  actionNames = "return,increment,decrement,assignn,assignv,addn,addv,subn,subv,lindirectv,rindirect,lindirectn,set,reset,toggle,set.v,reset.v,toggle.v,new.room,new.room.v,load.logics,load.logics.v,call,call.v,load.pic,draw.pic,show.pic,discard.pic,overlay.pic,show.pri.screen,load.view,load.view.v,discard.view,animate.obj,unanimate.all,draw,erase,position,position.v,get.posn,reposition,set.view,set.view.v,set.loop,set.loop.v,fix.loop,release.loop,set.cel,set.cel.v,last.cel,current.cel,current.loop,current.view,number.of.loops,set.priority,set.priority.v,release.priority,get.priority,stop.update,start.update,force.update,ignore.horizon,observe.horizon,set.horizon,object.on.water,object.on.land,object.on.anything,ignore.objs,observe.objs,distance,stop.cycling,start.cycling,normal.cycle,end.of.loop,reverse.cycle,reverse.loop,cycle.time,stop.motion,start.motion,step.size,step.time,move.obj,move.obj.v,follow.ego,wander,normal.motion,set.dir,get.dir,ignore.blocks,observe.blocks,block,unblock,get,get.v,drop,put,put.v,get.room.v,load.sound,sound,stop.sound,print,print.v,display,display.v,clear.lines,text.screen,graphics,set.cursor.char,set.text.attribute,shake.screen,configure.screen,status.line.on,status.line.off,set.string,get.string,word.to.string,parse,get.num,prevent.input,accept.input,set.key,add.to.pic,add.to.pic.v,status,save.game,restore.game,init.disk,restart.game,show.obj,random,program.control,player.control,obj.status.v,quit,show.mem,pause,echo.line,cancel.line,init.joy,toggle.monitor,version,script.size,set.game.id,log,set.scan.start,reset.scan.start,reposition.to,reposition.to.v,trace.on,trace.info,print.at,print.at.v,discard.view.v,clear.text.rect,set.upper.left,set.menu,set.menu.item,submit.menu,enable.item,disable.item,menu.input,show.obj.v,open.dialogue,close.dialogue,mul.n,mul.v,div.n,div.v,close.window,unknown170,unknown171,unknown172,unknown173,unknown174,unknown175,unknown176,unknown177,unknown178,unknown179,unknown180,unknown181"
  actionCounts = [0,1,1,2,2,2,2,2,2,2,2,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,0,1,1,1,1,0,1,1,3,3,3,3,2,2,2,2,1,1,2,2,2,2,2,2,2,2,2,1,2,1,1,1,1,1,1,1,1,1,1,1,3,1,1,1,2,1,2,2,1,1,2,2,5,5,3,1,1,2,2,1,1,4,0,1,1,1,2,2,2,1,2,0,1,1,3,3,3,0,0,1,2,1,3,0,0,2,5,2,1,2,0,0,3,7,7,0,0,0,0,0,1,3,0,0,1,1,0,0,0,0,0,0,0,1,1,1,0,0,3,3,0,3,4,4,1,5,2,1,2,0,1,1,0,1,0,0,2,2,2,2,0,1,0,0,0,1,1,0,1,0,4,2,0]

proc le16(data: openArray[byte], at: int): int =
  if at < 0 or at + 2 > data.len: raise newException(ValueError, "truncated AGI LOGIC word")
  int(data[at]) or int(data[at + 1]) shl 8

proc signed16(data: openArray[byte], at: int): int =
  let n = le16(data, at); (if n >= 0x8000: n - 0x10000 else: n)

proc escapeText(data: openArray[byte]): string =
  for b in data:
    if b == 10: result.add "\\n"
    elif b == 13: result.add "\\r"
    elif b == byte('"'): result.add "\\\""
    elif b == byte('\\'): result.add "\\\\"
    elif b >= 0x20 and b < 0x7f: result.add char(b)
    else: result.add "\\x" & toHex(b, 2)

proc messageArgument(action: string): int =
  ## Return the zero-based argument containing a literal message number.
  case action
  of "print", "set.cursor.char", "get.num", "log", "print.at",
      "set.game.id", "set.menu", "set.menu.item": 0
  of "set.string", "get.string": 1
  of "display": 2
  else: -1

proc operandKind(action: string, index: int): OperandKind =
  ## The supplied command table's semantic operand types. Unknown and plain
  ## numeric fields deliberately retain their byte representation.
  if action in ["equaln", "lessn", "greatern"]: return if index == 0: okVariable else: okNumber
  if action in ["equalv", "lessv", "greaterv"]: return okVariable
  if action in ["isset"]: return okFlag
  if action in ["issetv"]: return okVariable
  if action in ["has"]: return okInventoryObject
  if action == "obj.in.room": return if index == 0: okInventoryObject else: okVariable
  if action in ["posn", "obj.in.box", "center.posn", "right.posn"]:
    return if index == 0: okScreenObject else: okNumber
  if action == "controller": return okController
  if action == "compare.strings": return okString

  if action in ["increment", "decrement", "set.v", "reset.v", "toggle.v",
      "new.room.v", "load.logics.v", "call.v", "load.pic", "draw.pic",
      "discard.pic", "overlay.pic", "load.view.v", "get.v", "show.obj.v",
      "obj.status.v", "discard.view.v", "print.v", "add.to.pic.v"]: return okVariable
  if action in ["assignn", "addn", "subn", "lindirectn", "mul.n", "div.n"]:
    return if index == 0: okVariable else: okNumber
  if action in ["assignv", "addv", "subv", "lindirectv", "rindirect",
      "put.v", "get.room.v", "mul.v", "div.v"]: return okVariable
  if action in ["set", "reset", "toggle"]: return okFlag
  if action == "new.room": return okRoom
  if action in ["load.logics", "call"]: return okLogic
  if action in ["load.view", "discard.view"]: return okView
  if action == "load.sound": return okSound
  if action == "sound": return if index == 0: okSound else: okFlag

  if action in ["animate.obj", "draw", "erase", "fix.loop", "release.loop",
      "release.priority", "stop.update", "start.update", "force.update",
      "ignore.horizon", "observe.horizon", "object.on.water", "object.on.land",
      "object.on.anything", "ignore.objs", "observe.objs", "stop.cycling",
      "start.cycling", "normal.cycle", "reverse.cycle", "stop.motion",
      "start.motion", "wander", "normal.motion", "ignore.blocks",
      "observe.blocks"]: return okScreenObject
  if action == "set.view": return if index == 0: okScreenObject else: okView
  if action in ["position", "set.loop", "set.cel", "set.priority",
      "reposition.to"]: return if index == 0: okScreenObject else: okNumber
  if action in ["position.v", "get.posn", "reposition", "set.view.v",
      "set.loop.v", "set.cel.v", "last.cel", "current.cel", "current.loop",
      "current.view", "number.of.loops", "set.priority.v", "get.priority",
      "cycle.time", "step.size", "step.time", "set.dir", "get.dir",
      "reposition.to.v"]: return if index == 0: okScreenObject else: okVariable
  if action == "distance": return if index < 2: okScreenObject else: okVariable
  if action in ["end.of.loop", "reverse.loop"]:
    return if index == 0: okScreenObject else: okFlag
  if action in ["move.obj", "follow.ego"]: return if index == 0: okScreenObject elif index == 4 or (action == "follow.ego" and index == 2): okFlag else: okNumber
  if action == "move.obj.v": return if index == 0: okScreenObject elif index == 4: okFlag else: okVariable
  if action in ["get", "drop", "put"]: return if index == 0: okInventoryObject else: okNumber
  if action in ["show.obj", "add.to.pic"] and index == 0: return okView
  if action == "set.key" and index == 2: return okController
  if action == "trace.info" and index == 0: return okLogic

  if index == messageArgument(action): return okMessage
  if action in ["set.string", "get.string"] and index == 0: return okString
  if action == "word.to.string": return if index == 0: okWord else: okString
  if action == "parse": return okString
  if action == "get.num" and index == 1: return okVariable
  if action == "display.v": return okVariable
  if action == "print.at.v": return if index == 0: okVariable else: okNumber
  if action == "set.menu.item" and index == 1: return okController
  if action in ["enable.item", "disable.item"]: return okController
  okNumber

proc typedOperand(value: int, kind: OperandKind): string =
  case kind
  of okVariable: "v" & $value
  of okFlag: "f" & $value
  of okScreenObject: "o" & $value
  of okInventoryObject: "i" & $value
  of okController: "c" & $value
  of okString: "s" & $value
  of okWord: "w" & $value
  of okMessage: "m" & $value
  of okLogic: "logic" & $value
  of okRoom: "room" & $value
  of okView: "view" & $value
  of okSound: "sound" & $value
  of okNumber: $value

proc messages(data: openArray[byte], section: int, encrypted: bool): seq[string] =
  if section == data.len: return
  if section + 3 > data.len: raise newException(ValueError, "truncated AGI LOGIC message header")
  let count = int(data[section]); let textStart = section + 3 + count * 2
  if textStart > data.len: raise newException(ValueError, "truncated AGI LOGIC message offsets")
  var clear = newSeq[byte](data.len - textStart); let key = "Avis Durgan"
  for i in 0 ..< clear.len:
    clear[i] = if encrypted: data[textStart+i] xor byte(key[i mod key.len])
      else: data[textStart+i]
  result = newSeq[string](count)
  for i in 0 ..< count:
    let relative = le16(data, section + 3 + i*2)
    if relative == 0: continue
    let start = section + 1 + relative
    if start < textStart or start >= data.len: raise newException(ValueError, "AGI LOGIC message offset is outside text data")
    var finish = start
    while finish < data.len and clear[finish-textStart] != 0: inc finish
    if finish >= data.len: raise newException(ValueError, "unterminated AGI LOGIC message")
    result[i] = escapeText(clear.toOpenArray(start-textStart, finish-textStart-1))

proc decodeAgiLogic*(data: openArray[byte], messagesEncrypted = true): string =
  if data.len < 2: raise newException(ValueError, "truncated AGI LOGIC header")
  let codeEnd = 2 + le16(data, 0)
  if codeEnd > data.len: raise newException(ValueError, "AGI LOGIC code extends beyond resource")
  let msgs = messages(data, codeEnd, messagesEncrypted)
  let actions = actionNames.split(','); let tests = testNames.split(',')
  var at = 2; result = "code:\n"
  var knownPicVar = -1
  var knownPic = -1
  template need(n: int) =
    if at + n > codeEnd: raise newException(ValueError, "truncated AGI LOGIC instruction")
  while at < codeEnd:
    let offset = at-2; let opcode = int(data[at]); inc at
    result.add toHex(offset,4) & "  "
    if opcode == 0xfe:
      need(2); let jump = signed16(data,at); at += 2
      result.add "goto " & toHex(at-2+jump,4) & "\n"
      knownPicVar = -1
    elif opcode == 0xff:
      var terms, orTerms: seq[string]
      var negated, inOr = false
      while true:
        need(1); let test = int(data[at]); inc at
        if test == 0xff: break
        if test == 0xfd: negated = not negated; continue
        if test == 0xfc:
          if inOr:
            if orTerms.len == 0:
              raise newException(ValueError, "empty AGI LOGIC or group")
            terms.add "(" & orTerms.join(" || ") & ")"
            orTerms.setLen(0)
          inOr = not inOr
          continue
        if test <= 0 or test >= testCounts.len: raise newException(ValueError, "unknown AGI LOGIC test opcode")
        var args: seq[string]
        if test == 0x0e:
          need(1); let count = int(data[at]); inc at; need(count*2)
          for i in 0 ..< count: args.add "w" & $le16(data,at+i*2)
          at += count*2
        else:
          let count=testCounts[test]; need(count)
          for i in 0 ..< count:
            args.add typedOperand(int(data[at+i]), operandKind(tests[test], i))
          at += count
        let term = (if negated: "!" else: "") & tests[test] &
          "(" & args.join(", ") & ")"
        if inOr: orTerms.add term else: terms.add term
        negated=false
      if inOr: raise newException(ValueError, "unterminated AGI LOGIC or group")
      need(2); let jump=le16(data,at); at += 2
      result.add "if " & terms.join(" && ") & " else goto " & toHex(at-2+jump,4) & "\n"
      knownPicVar = -1
    elif opcode < actionCounts.len:
      let count=actionCounts[opcode]; need(count); var args: seq[string]
      var rawArgs: seq[int]
      let action = actions[opcode]
      for i in 0 ..< count:
        rawArgs.add int(data[at+i])
        args.add typedOperand(rawArgs[^1], operandKind(action, i))
      at += count
      let messageAt = messageArgument(action)
      var messageId = 0
      if messageAt >= 0:
        messageId = int(rawArgs[messageAt])
        if messageId > 0 and messageId <= msgs.len:
          args[messageAt] = "\"" & msgs[messageId-1] & "\""
      result.add action & "(" & args.join(", ") & ")"
      if messageId > 0 and messageId <= msgs.len:
        result.add "  ; message " & $messageId
      if action in ["load.pic", "draw.pic", "discard.pic", "overlay.pic"] and
          count == 1 and int(rawArgs[0]) == knownPicVar:
        result.add "  ; PIC " & $knownPic
      if opcode == 0xb1 and count == 1:
        result.add(if rawArgs[0] == 0: "  ; disable menu access" else:
          "  ; enable menu access")
      result.add "\n"
      if action == "assignn" and count == 2:
        knownPicVar = int(rawArgs[0])
        knownPic = int(rawArgs[1])
      elif not (action in ["load.pic", "draw.pic", "discard.pic", "overlay.pic"] and
          count == 1 and int(rawArgs[0]) == knownPicVar):
        knownPicVar = -1
    else: raise newException(ValueError, "unknown AGI LOGIC action opcode")
  result.add "\nmessages:\n"
  for i,msg in msgs: result.add $(i+1) & "  \"" & msg & "\"\n"
