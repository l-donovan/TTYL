//
//  TerminalContainer.swift
//  TTYL
//
//  Created by Luke Donovan on 8/23/21.
//

import Foundation
import SwiftUI

let cBell = Character(UnicodeScalar(27))

// Regular expressions
let exprMode = try! NSRegularExpression(pattern: #"\[(.+)([hl])"#, options: [])
let exprIterm = try! NSRegularExpression(pattern: #"\]1337;(.+)"# + "\\U00000007", options: [])
let exprIconName = try! NSRegularExpression(pattern: #"\]1;(.*)"# + "\\U00000007", options: [])
let exprWindowTitle = try! NSRegularExpression(pattern: #"\]2;(.*)"# + "\\U00000007", options: [])
let exprColor = try! NSRegularExpression(pattern: #"\[(\d*)m"#, options: [])
let exprFgColor1 = try! NSRegularExpression(pattern: #"\[38;5;(\d+)m"#, options: [])
let exprFgColor2 = try! NSRegularExpression(pattern: #"\[38;2;(\d+);(\d+);(\d+)m"#, options: [])
let exprBgColor1 = try! NSRegularExpression(pattern: #"\[48;5;(\d+)m"#, options: [])
let exprFinalTerm1 = try! NSRegularExpression(pattern: #"\]133;(\w+);?"# + "\\U00000007", options: [])
let exprFinalTerm2 = try! NSRegularExpression(pattern: #"\]133;(\w+);(\d+)"# + "\\U00000007", options: [])
let exprBracketedPaste = try! NSRegularExpression(pattern: #"\[?2004([hl])"#, options: [])
let exprMovementRel = try! NSRegularExpression(pattern: #"\[(\d*)([ABCDEF])"#, options: [])
let exprTerminalConfig = try! NSRegularExpression(pattern: #"\[(\d+);?(\d*);?(\d*)t"#, options: [])
// TODO: G
let exprMovementAbs = try! NSRegularExpression(pattern: #"\[(\d*);?(\d*)H"#, options: []) // TODO: this is not ideal
let exprEraseInDisplay = try! NSRegularExpression(pattern: #"\[(\d*)J"#, options: [])
let exprEraseInLine = try! NSRegularExpression(pattern: #"\[(\d*)K"#, options: [])
let exprDeviceStatusReport = try! NSRegularExpression(pattern: #"\[6n"#, options: [])

let defaultFgColor: ANSIColor = .named(.white)
let defaultBgColor: ANSIColor = .named(.black)

class TerminalContainer: ObservableObject {
    @Published var rowCount: UInt16
    @Published var colCount: UInt16
    @Published var currentRow: UInt16 = 0
    @Published var currentCol: UInt16 = 0
    @Published var terminalRows: [TerminalRow] = []
    @Published var historicalRows: [TerminalRow] = []
    @Published var title: String = ""
    
    var colorTable: [ColorCode: Color] = [:]
    var modes: [String: Bool] = [:]
    var ptyHandle: FileHandle?
    
    var inEscapeSequence: Bool = false
    var escapeSequence: String = ""
    
    var currentFgColor: ANSIColor = defaultFgColor
    var currentBgColor: ANSIColor = defaultBgColor
    
    var readingDeviceControlString: Bool = false
    var deviceControlString: String = ""
    var chunkIncomplete: Bool = false
    var printableText: String = ""
    var rowHistoryIdx: UInt16
    
    convenience init() {
        self.init(rows: 24, cols: 80)
    }
    
    init(rows: UInt16, cols: UInt16) {
        rowCount = rows
        colCount = cols
        rowHistoryIdx = rows
        
        var characters: [TerminalCharacter] = []
        
        for c in 0..<cols {
            characters.append(TerminalCharacter(id: c, value: " ", backgroundColor: .named(.black), foregroundColor: .named(.white)))
        }
        
        for r in 0..<rows {
            terminalRows.append(TerminalRow(id: r, characters: characters))
        }
                
        runShell()
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            if self.keyDown(with: $0) {
                return nil // Needed to get rid of purr sound
            }
            
            return $0
        }
    }
    
    func keyDown(with event: NSEvent) -> Bool {
        let char: UnicodeScalar = (event.charactersIgnoringModifiers?.unicodeScalars.first)!
        
        // For command key shortcuts
        if event.modifierFlags.contains(.command) {
            switch char {
            case "q":
                return false
            default:
                return true
            }
        }
        
        // For ASCII keypresses
        if char.isASCII {
            sendText(String(char))
            return true
        }
        
        // For anything else
        return false
    }
    
    @objc private func outputReceived(notification: NSNotification) {
        let output = String(decoding: ptyHandle!.availableData, as: UTF8.self)
        writeToShell(output)
        ptyHandle?.waitForDataInBackgroundAndNotify()
    }
    
    func sendText(_ text: String) {
        ptyHandle?.write(text.data(using: .utf8) ?? .init())
    }
    
    func processTextChunk(_ text: String, firstChunk: Bool) -> String {
        var found: Bool = false
        var leftovers: String = ""
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        
        exprMode.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }

            if match.numberOfRanges == exprMode.numberOfCaptureGroups + 1,
               let captureRangeMode = Range(match.range(at: 1), in: text),
               let captureRangeEnable = Range(match.range(at: 2), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let mode = String(text[captureRangeMode])
                let enabled = text[captureRangeEnable] == "h"
                
                modes[mode] = enabled
                
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprIterm.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }

            if match.numberOfRanges == exprIterm.numberOfCaptureGroups + 1,
               let captureRange = Range(match.range(at: 1), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let pairs = text[captureRange].split(separator: ";")
                for pairStr in pairs {
                    let pair = String(pairStr).split(separator: "=")
                    let (key, val) = (pair[0], pair[1])
                }
                
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprIconName.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }

            if match.numberOfRanges == exprIconName.numberOfCaptureGroups + 1,
               let captureRange = Range(match.range(at: 1), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let name = text[captureRange]
                print("Icon name: \"\(name)\"")
                
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprWindowTitle.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }

            if match.numberOfRanges == exprWindowTitle.numberOfCaptureGroups + 1,
               let captureRange = Range(match.range(at: 1), in: text),
               let leftoversRange = Range(match.range, in: text) {
                title = String(text[captureRange])
                
                
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprColor.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }
            
            if match.numberOfRanges == exprColor.numberOfCaptureGroups + 1,
               let captureRange = Range(match.range(at: 1), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let colorCode = UInt8(text[captureRange]) ?? 0
                
                if colorCode == 0 {
                    currentFgColor = defaultFgColor
                    currentBgColor = defaultBgColor
                } else if colorCode > 29 && colorCode < 38 {
                    currentFgColor = .named(.init(rawValue: colorCode - 30) ?? .white)
                } else if colorCode == 39 {
                    currentFgColor = defaultFgColor
                } else if colorCode > 39 && colorCode < 48 {
                    currentBgColor = .named(.init(rawValue: colorCode - 40) ?? .black)
                } else if colorCode > 89 && colorCode < 98 {
                    currentFgColor = .named((.init(rawValue: colorCode - 82) ?? .white))
                } else if colorCode > 99 && colorCode < 108 {
                    currentBgColor = .named(.init(rawValue: colorCode - 92) ?? .black)
                }
                
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprFinalTerm1.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }

            if match.numberOfRanges == exprFinalTerm1.numberOfCaptureGroups + 1,
               let captureRange = Range(match.range(at: 1), in: text),
               let leftoversRange = Range(match.range, in: text) {
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprFinalTerm2.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }

            if match.numberOfRanges == exprFinalTerm2.numberOfCaptureGroups + 1,
               let captureRange = Range(match.range(at: 1), in: text),
               let leftoversRange = Range(match.range, in: text) {
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprFgColor1.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }
            
            if match.numberOfRanges == exprFgColor1.numberOfCaptureGroups + 1,
               let captureRange = Range(match.range(at: 1), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let colorCode = UInt8(text[captureRange]) ?? 0
                
                currentFgColor = {
                    if colorCode < 16 {
                        return .named(.init(rawValue: colorCode) ?? .black)
                    } else if colorCode < 232 {
                        return .cube(colorCode)
                    } else {
                        return .grayscale(colorCode)
                    }
                }()
                
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprFgColor2.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }
            
            if match.numberOfRanges == exprFgColor2.numberOfCaptureGroups + 1,
               let captureRangeR = Range(match.range(at: 1), in: text),
               let captureRangeG = Range(match.range(at: 2), in: text),
               let captureRangeB = Range(match.range(at: 3), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let r = UInt8(text[captureRangeR]) ?? 0
                let g = UInt8(text[captureRangeG]) ?? 0
                let b = UInt8(text[captureRangeB]) ?? 0
                currentFgColor = .rgb(r, g, b)
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprBgColor1.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }
            
            if match.numberOfRanges == exprBgColor1.numberOfCaptureGroups + 1,
               let captureRange = Range(match.range(at: 1), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let colorCode = UInt8(text[captureRange]) ?? 0
                
                currentBgColor = {
                    if colorCode < 16 {
                        return .named(.init(rawValue: colorCode) ?? .black)
                    } else if colorCode < 232 {
                        return .cube(colorCode)
                    } else {
                        return .grayscale(colorCode)
                    }
                }()
                
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprBracketedPaste.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }
            
            if match.numberOfRanges == exprBracketedPaste.numberOfCaptureGroups + 1,
               let captureRange = Range(match.range(at: 1), in: text),
               let leftoversRange = Range(match.range, in: text) {
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprMovementRel.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }
            
            if match.numberOfRanges == exprMovementRel.numberOfCaptureGroups + 1,
               let captureRangeNum = Range(match.range(at: 1), in: text),
               let captureRangeCmd = Range(match.range(at: 2), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let num = UInt16(text[captureRangeNum]) ?? 1
                let cmd = text[captureRangeCmd]
                
                switch cmd {
                case "A":
                    if currentRow > (num - 1) {
                        currentRow -= num
                    }
                    break
                case "B":
                    if currentRow < (rowCount - num) {
                        currentRow += num
                    }
                    break
                case "C":
                    if currentCol < (colCount - num) {
                        currentCol += num
                    }
                    break
                case "D":
                    if currentCol > (num - 1) {
                        currentCol -= num
                    }
                    break
                case "E":
                    if currentRow < (rowCount - num) {
                        currentRow += num
                        currentCol = 0
                    }
                    break
                case "F":
                    if currentRow > (num - 1) {
                        currentRow -= num
                        currentCol = 0
                    }
                    break
                default:
                    break
                }
                
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprMovementAbs.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }
            
            if match.numberOfRanges == exprMovementAbs.numberOfCaptureGroups + 1,
               let captureRangeRow = Range(match.range(at: 1), in: text),
               let captureRangeCol = Range(match.range(at: 2), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let row = (UInt16(text[captureRangeRow]) ?? 1) - 1
                let col = (UInt16(text[captureRangeCol]) ?? 1) - 1
                currentRow = row
                currentCol = col
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprEraseInDisplay.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }
            
            if match.numberOfRanges == exprEraseInDisplay.numberOfCaptureGroups + 1,
               let captureRangeMode = Range(match.range(at: 1), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let mode = UInt8(text[captureRangeMode]) ?? 0
                
                switch mode {
                case 0:
                    for col in currentCol..<colCount {
                        terminalRows[Int(currentRow)].characters[Int(col)].value = " "
                    }
                    for row in (currentRow + 1)..<rowCount {
                        for col in 0..<colCount {
                            terminalRows[Int(row)].characters[Int(col)].value = " "
                        }
                    }
                    break
                case 1:
                    for col in 0...currentCol {
                        terminalRows[Int(currentRow)].characters[Int(col)].value = " "
                    }
                    for row in 0..<currentRow {
                        for col in 0..<colCount {
                            terminalRows[Int(row)].characters[Int(col)].value = " "
                        }
                    }
                    break
                case 3:
                    historicalRows = []
                    rowHistoryIdx = rowCount
                    // Intentional fallthough
                case 2:
                    for row in 0..<rowCount {
                        for col in 0..<colCount {
                            terminalRows[Int(row)].characters[Int(col)].value = " "
                        }
                    }
                    currentRow = 0
                    currentCol = 0
                    break
                default:
                    break
                }
                
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprEraseInLine.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }
            
            if match.numberOfRanges == exprEraseInLine.numberOfCaptureGroups + 1,
               let captureRangeMode = Range(match.range(at: 1), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let mode = UInt8(text[captureRangeMode]) ?? 0
                
                switch mode {
                case 0:
                    for col in currentCol..<colCount {
                        terminalRows[Int(currentRow)].characters[Int(col)].value = " "
                    }
                    break
                case 1:
                    for col in 0...currentCol {
                        terminalRows[Int(currentRow)].characters[Int(col)].value = " "
                    }
                    break
                case 2:
                    for col in 0..<colCount {
                        terminalRows[Int(currentRow)].characters[Int(col)].value = " "
                    }
                    break
                default:
                    break
                }
                
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprTerminalConfig.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }
            
            if match.numberOfRanges == exprTerminalConfig.numberOfCaptureGroups + 1,
               let captureRangeCmd = Range(match.range(at: 1), in: text),
               let captureRangeNumA = Range(match.range(at: 2), in: text),
               let captureRangeNumB = Range(match.range(at: 3), in: text),
               let leftoversRange = Range(match.range, in: text) {
                let mode = UInt8(text[captureRangeCmd]) ?? 0
                
                switch mode {
                case 20:
                    break
                case 21:
                    break
                case 22:
                    break
                case 23:
                    break
                default:
                    print("Unimplemented terminal config seq: \(mode)")
                    break
                }
                
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        exprDeviceStatusReport.enumerateMatches(in: text, options: [], range: nsrange) { (match, _, stop) in
            guard let match = match else { return }
            
            if match.numberOfRanges == exprDeviceStatusReport.numberOfCaptureGroups + 1,
               let leftoversRange = Range(match.range, in: text) {
                sendText(String(UnicodeScalar(27)) + "[\(currentRow + 1);\(currentCol + 1)R")
                leftovers = String(text[leftoversRange.upperBound...])
                found = true
                stop.pointee = true
            }
        }
        
        if text.starts(with: "[39;49m") {
            currentFgColor = defaultFgColor
            currentBgColor = defaultBgColor
            leftovers = String(text[text.index(text.startIndex, offsetBy: 7)...])
            found = true
        } else if text.first == "P" {
            readingDeviceControlString = true
            leftovers = String(text[text.index(text.startIndex, offsetBy: 1)...])
            found = true
        } else if text.first == "\\" {
            readingDeviceControlString = false
            print("Got device control string \"\(deviceControlString)\"")
            deviceControlString = ""
            leftovers = String(text[text.index(text.startIndex, offsetBy: 1)...])
            found = true
        } else if text.first == "=" {
            // TODO: Set Application Keypad Mode (DECKPAM)
            leftovers = String(text[text.index(text.startIndex, offsetBy: 1)...])
            found = true
        } else if text.first == ">" {
            // TODO: Reset Application Keypad Mode (DECKPNM)
            leftovers = String(text[text.index(text.startIndex, offsetBy: 1)...])
            found = true
        }
        
        chunkIncomplete = false
                        
        if !found {
            if !firstChunk { // TODO: First *OR ONLY* chunk
                print("Incomplete chunk: \"\(text)\"")
                chunkIncomplete = true
            }
            
            print("Unknown: \"\(text)\"")
            
            return text
        }

        return leftovers
    }
    
    func incRow() {
        currentRow += 1
        
        if currentRow > (rowCount - 1) {
            currentRow = rowCount - 1
            
            terminalRows[0].id = rowHistoryIdx
            historicalRows.append(terminalRows[0])
            rowHistoryIdx += 1
            
            for idx in 0..<(rowCount - 1) {
                terminalRows[Int(idx)] = terminalRows[Int(idx) + 1]
                terminalRows[Int(idx)].id = idx
            }
            
            var characters: [TerminalCharacter] = []
            
            for c in 0..<colCount {
                characters.append(TerminalCharacter(id: c, value: " ", backgroundColor: .named(.black), foregroundColor: .named(.white)))
            }
            
            terminalRows[Int(rowCount) - 1] = TerminalRow(id: rowCount - 1, characters: characters)
        }
    }
    
    func writeToShell(_ text: String) {
        let chunks = text.split(separator: Character(UnicodeScalar(27)))
        
        if chunks.isEmpty {
            // Shell is dead. Close the App
            NSApplication.shared.terminate(self)
        }
        
//        print(chunks)
        
        for (idx, chunk) in chunks.enumerated() {
            if chunkIncomplete {
                printableText = processTextChunk(printableText + String(chunk), firstChunk: idx == 0)
            } else {
                printableText = processTextChunk(String(chunk), firstChunk: idx == 0)
            }
            
            if chunkIncomplete || printableText.isEmpty {
                continue
            }
            
            if readingDeviceControlString {
                deviceControlString += printableText
                continue
            }
            
            for el in printableText {
                if el.asciiValue == 10 {
                    currentCol = 0
                    incRow()
                } else if el.asciiValue == 13 {
                    currentCol = 0
                } else if el.asciiValue == 8 {
                    if currentCol > 0 {
                        currentCol -= 1
                    } else {
                        currentRow -= 1
                        currentCol = colCount - 1
                    }
                } else {
                    if currentCol > (colCount - 1) {
                        currentCol = 0
                        incRow()
                    }

                    terminalRows[Int(currentRow)].characters[Int(currentCol)].value = el
                    terminalRows[Int(currentRow)].characters[Int(currentCol)].foregroundColor = currentFgColor
                    terminalRows[Int(currentRow)].characters[Int(currentCol)].backgroundColor = currentBgColor
                    
                    currentCol += 1
                }
            }
        }
    }
    
    func runShell() {
        var pty: Int32 = 0
        var tty: Int32 = 0
        
        var windowSize = winsize(ws_row: rowCount, ws_col: colCount, ws_xpixel: 0, ws_ypixel: 0)
        
        if openpty(&pty, &tty, nil, nil, &windowSize) == -1 {
            print("Failed to open pty")
        }
        
        ptyHandle = FileHandle(fileDescriptor: pty, closeOnDealloc: true)
        let ttyHandle = FileHandle(fileDescriptor: tty, closeOnDealloc: true)
        
        let shell = Process()
        shell.environment = [
            "TERM": "xterm-256color"
        ]
        shell.executableURL = URL(fileURLWithPath: "/usr/local/bin/zsh")
        shell.arguments = []
        shell.standardInput = ttyHandle
        shell.standardOutput = ttyHandle
        shell.standardError = ttyHandle
        
        do {
            try shell.run()
            try ttyHandle.close()
        } catch {
            print(error)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.outputReceived), name: NSNotification.Name.NSFileHandleDataAvailable, object: nil)
    }
    
    deinit {
        
    }
}
