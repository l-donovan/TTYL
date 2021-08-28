//
//  TerminalObjects.swift
//  TTYL
//
//  Created by Luke Donovan on 8/23/21.
//

import Foundation
import SwiftUI

enum ColorCode: UInt8 {
    case black = 0
    case red = 1
    case green = 2
    case yellow = 3
    case blue = 4
    case magenta = 5
    case cyan = 6
    case white = 7
    case brightBlack = 8
    case brightRed = 9
    case brightGreen = 10
    case brightYellow = 11
    case brightBlue = 12
    case brightMagenta = 13
    case brightCyan = 14
    case brightWhite = 15
}

let defaultColorTable: [ColorCode: Color] = [
    .black: .black,
    .red: .red,
    .green: .green,
    .yellow: .yellow,
    .blue: .blue,
    .magenta: Color(red: 0.83, green: 0.22, blue: 0.83),
    .cyan: Color(red: 0.2, green: 0.73, blue: 0.78),
    .white: Color(white: 0.8),
    .brightBlack: Color(white: 0.51),
    .brightRed: Color(red: 0.99, green: 0.22, blue: 0.12),
    .brightGreen: Color(red: 0.19, green: 0.91, blue: 0.13),
    .brightYellow: Color(red: 0.92, green: 0.93, blue: 0.14),
    .brightBlue: Color(red: 0.35, green: 0.2, blue: 1.0),
    .brightMagenta: Color(red: 0.98, green: 0.21, blue: 0.97),
    .brightCyan: Color(red: 0.08, green: 0.94, blue: 0.94),
    .brightWhite: .white
]

enum ANSIColor: Hashable {
    case named(ColorCode)
    case cube(UInt8)
    case grayscale(UInt8)
    case rgb(UInt8, UInt8, UInt8)
    
    func getColorValue(_ colorTable: [ColorCode: Color] = defaultColorTable) -> Color {
        switch self {
        case .named(let code):
            return colorTable[code] ?? defaultColorTable[code] ?? Color(red: 0.0, green: 0.0, blue: 0.0)
        case .cube(var cube):
            cube -= 16
            let b = cube % 6
            cube = (cube - b) / 6
            let g = cube % 6
            let r = (cube - g) / 6
            return Color(red: Double(r) / 5.0, green: Double(g) / 5.0, blue: Double(b) / 5.0)
        case .grayscale(let gray):
            return Color(white: Double(gray - 232) / 23.0)
        case .rgb(let r, let g, let b):
            return Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
        }
    }
}

struct TerminalRow: Identifiable, Hashable {
    static func == (lhs: TerminalRow, rhs: TerminalRow) -> Bool {
        return lhs.id == rhs.id
    }
    
    var id: UInt16
    var characters: [TerminalCharacter]
}

struct TerminalCharacter: Identifiable, Hashable {
    static func == (lhs: TerminalCharacter, rhs: TerminalCharacter) -> Bool {
        return lhs.id == rhs.id
    }
    
    var id: UInt16
    var value: Character
    var backgroundColor: ANSIColor
    var foregroundColor: ANSIColor
}
