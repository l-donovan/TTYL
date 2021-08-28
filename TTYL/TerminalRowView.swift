//
//  TerminalRowView.swift
//  TTYL
//
//  Created by Luke Donovan on 8/23/21.
//

import Foundation
import SwiftUI

let cursorChar = "█"

struct TerminalRowView: View {
    var terminalRow: TerminalRow
    var colorTable: [ColorCode: Color]
    var cursorRow: UInt16
    var cursorCol: UInt16
        
    func isAtCursor(_ char: TerminalCharacter) -> Bool {
        return char.id == cursorCol && terminalRow.id == cursorRow
    }
    
    var body: some View {
        terminalRow.characters.map { character in
            let isCursor = isAtCursor(character)

            return Text(isCursor ? cursorChar : String(character.value))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(isCursor ? .white : character.foregroundColor.getColorValue(colorTable))
                // Background color is not yet supported, it should possible with attribute strings in macOS 12
                // Will look something like:
                // Text(String(character.value))
                //   .font(.system(size: 12, weight: .regular, design: .monospaced)) {
                //     $0.foregroundColor = isCursor ? .white : character.foregroundColor.getColorValue(colorTable)
                //     $0.backgroundColor = isCursor ? .black : character.backgroundColor.getColorValue(colorTable)
                // }
        }.reduce(Text(""), +)
    }
}

struct TerminalRowView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalRowView(terminalRow: TerminalRow(id: 0, characters: []), colorTable: defaultColorTable, cursorRow: 0, cursorCol: 0)
    }
}
