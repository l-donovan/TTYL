//
//  ContentView.swift
//  TTYL
//
//  Created by Luke Donovan on 8/23/21.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var terminalContainer = TerminalContainer()
    
    var body: some View {
        ScrollViewReader { scrollViewProxy in
            ScrollView {
                let rows = terminalContainer.historicalRows + terminalContainer.terminalRows
                
                LazyVStack {
                    ForEach(rows) { row in
                        TerminalRowView(terminalRow: row, colorTable: terminalContainer.colorTable,
                                        cursorRow: terminalContainer.currentRow, cursorCol: terminalContainer.currentCol)
                            .id(row.id)
                    }.onChange(of: rows, perform: { value in
                        scrollViewProxy.scrollTo(terminalContainer.rowCount - 1)
                    })
                }.onAppear {
                    terminalContainer.ptyHandle?.waitForDataInBackgroundAndNotify()
                }
            }
        }
        .padding(6.0)
        .navigationTitle(terminalContainer.title.isEmpty ? "TTYL" : terminalContainer.title)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
