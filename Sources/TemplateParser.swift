// The MIT License
//
// Copyright (c) 2015 Gwendal Roué
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


import Foundation

protocol TemplateTokenConsumer {
    func parser(_ parser:TemplateParser, shouldContinueAfterParsingToken token:TemplateToken) -> Bool
    func parser(_ parser:TemplateParser, didFailWithError error:Error)
}

final class TemplateParser {
    let tokenConsumer: TemplateTokenConsumer
    fileprivate let tagDelimiterPair: TagDelimiterPair

    // UTF-8 character constants for better readability
    private static let newlineUtf8: UInt8 = Character("\n").asciiValue!
    private static let exclamationUtf8: UInt8 = Character("!").asciiValue!
    private static let hashUtf8: UInt8 = Character("#").asciiValue!
    private static let caretUtf8: UInt8 = Character("^").asciiValue!
    private static let dollarUtf8: UInt8 = Character("$").asciiValue!
    private static let slashUtf8: UInt8 = Character("/").asciiValue!
    private static let greaterThanUtf8: UInt8 = Character(">").asciiValue!
    private static let lessThanUtf8: UInt8 = Character("<").asciiValue!
    private static let ampersandUtf8: UInt8 = Character("&").asciiValue!
    private static let percentUtf8: UInt8 = Character("%").asciiValue!

    init(tokenConsumer: TemplateTokenConsumer, tagDelimiterPair: TagDelimiterPair) {
        self.tokenConsumer = tokenConsumer
        self.tagDelimiterPair = tagDelimiterPair
    }

    func parse(_ templateString:String, templateID: TemplateID?) {
        // Convert to Array for O(1) random access performance.
        // We need random access because the parser:
        // 1. Jumps ahead when finding multi-character delimiters
        // 2. Looks back to create content slices
        // 3. Accesses arbitrary positions for tag type checking
        // Direct UTF-8 view iteration would be O(n) for index operations.
        let utf8 = templateString.utf8
        let utf8Array = Array(utf8)
        let count = utf8Array.count

        var currentDelimiters = ParserTagDelimiters(tagDelimiterPair: tagDelimiterPair)

        var state: State = .start
        var lineNumber = 1
        var i = 0

        while i < count {
            let c = utf8Array[i]

            switch state {
            case .start:
                if c == Self.newlineUtf8 {
                    state = .text(startIndex: i, startLineNumber: lineNumber)
                    lineNumber += 1
                } else if isAt(i, bytes: currentDelimiters.unescapedTagStartBytes, in: utf8Array) {
                    state = .unescapedTag(startIndex: i, startLineNumber: lineNumber)
                    i += currentDelimiters.unescapedTagStartLength - 1
                } else if isAt(i, bytes: currentDelimiters.setDelimitersStartBytes, in: utf8Array) {
                    state = .setDelimitersTag(startIndex: i, startLineNumber: lineNumber)
                    i += currentDelimiters.setDelimitersStartLength - 1
                } else if isAt(i, bytes: currentDelimiters.tagStartBytes, in: utf8Array) {
                    state = .tag(startIndex: i, startLineNumber: lineNumber)
                    i += currentDelimiters.tagStartLength - 1
                } else {
                    state = .text(startIndex: i, startLineNumber: lineNumber)
                }
            case .text(let startIndex, let startLineNumber):
                if c == Self.newlineUtf8 {
                    lineNumber += 1
                } else if isAt(i, bytes: currentDelimiters.unescapedTagStartBytes, in: utf8Array) {
                    if startIndex != i {
                        let textData = Data(utf8Array[startIndex..<i])
                        let text = String(data: textData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .text(text: text),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: i)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    }
                    state = .unescapedTag(startIndex: i, startLineNumber: lineNumber)
                    i += currentDelimiters.unescapedTagStartLength - 1
                } else if isAt(i, bytes: currentDelimiters.setDelimitersStartBytes, in: utf8Array) {
                    if startIndex != i {
                        let textData = Data(utf8Array[startIndex..<i])
                        let text = String(data: textData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .text(text: text),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: i)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    }
                    state = .setDelimitersTag(startIndex: i, startLineNumber: lineNumber)
                    i += currentDelimiters.setDelimitersStartLength - 1
                } else if isAt(i, bytes: currentDelimiters.tagStartBytes, in: utf8Array) {
                    if startIndex != i {
                        let textData = Data(utf8Array[startIndex..<i])
                        let text = String(data: textData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .text(text: text),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: i)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    }
                    state = .tag(startIndex: i, startLineNumber: lineNumber)
                    i += currentDelimiters.tagStartLength - 1
                }
            case .tag(let startIndex, let startLineNumber):
                if c == Self.newlineUtf8 {
                    lineNumber += 1
                } else if isAt(i, bytes: currentDelimiters.tagEndBytes, in: utf8Array) {
                    let tagInitialIndex = startIndex + currentDelimiters.tagStartLength
                    let tagInitial = utf8Array[tagInitialIndex]
                    let tokenEndIndex = i + currentDelimiters.tagEndLength

                    switch tagInitial {
                    case Self.exclamationUtf8:
                        let token = TemplateToken(
                            type: .comment,
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: tokenEndIndex)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case Self.hashUtf8:
                        let contentData = Data(utf8Array[(tagInitialIndex + 1)..<i])
                        let content = String(data: contentData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .section(content: content, tagDelimiterPair: currentDelimiters.tagDelimiterPair),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: tokenEndIndex)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case Self.caretUtf8:
                        let contentData = Data(utf8Array[(tagInitialIndex + 1)..<i])
                        let content = String(data: contentData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .invertedSection(content: content, tagDelimiterPair: currentDelimiters.tagDelimiterPair),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: tokenEndIndex)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case Self.dollarUtf8:
                        let contentData = Data(utf8Array[(tagInitialIndex + 1)..<i])
                        let content = String(data: contentData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .block(content: content),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: tokenEndIndex)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case Self.slashUtf8:
                        let contentData = Data(utf8Array[(tagInitialIndex + 1)..<i])
                        let content = String(data: contentData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .close(content: content),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: tokenEndIndex)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case Self.greaterThanUtf8:
                        let contentData = Data(utf8Array[(tagInitialIndex + 1)..<i])
                        let content = String(data: contentData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .partial(content: content),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: tokenEndIndex)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case Self.lessThanUtf8:
                        let contentData = Data(utf8Array[(tagInitialIndex + 1)..<i])
                        let content = String(data: contentData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .partialOverride(content: content),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: tokenEndIndex)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case Self.ampersandUtf8:
                        let contentData = Data(utf8Array[(tagInitialIndex + 1)..<i])
                        let content = String(data: contentData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .unescapedVariable(content: content, tagDelimiterPair: currentDelimiters.tagDelimiterPair),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: tokenEndIndex)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case Self.percentUtf8:
                        let contentData = Data(utf8Array[(tagInitialIndex + 1)..<i])
                        let content = String(data: contentData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .pragma(content: content),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: tokenEndIndex)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    default:
                        let contentData = Data(utf8Array[tagInitialIndex..<i])
                        let content = String(data: contentData, encoding: .utf8)!
                        let token = TemplateToken(
                            type: .escapedVariable(content: content, tagDelimiterPair: currentDelimiters.tagDelimiterPair),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            utf8StartIndex: startIndex,
                            utf8EndIndex: tokenEndIndex)
                        if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    }
                    state = .start
                    i += currentDelimiters.tagEndLength - 1
                }
                break
            case .unescapedTag(let startIndex, let startLineNumber):
                if c == Self.newlineUtf8 {
                    lineNumber += 1
                } else if isAt(i, bytes: currentDelimiters.unescapedTagEndBytes, in: utf8Array) {
                    let tagInitialIndex = startIndex + currentDelimiters.unescapedTagStartLength
                    let contentData = Data(utf8Array[tagInitialIndex..<i])
                    let content = String(data: contentData, encoding: .utf8)!
                    let tokenEndIndex = i + currentDelimiters.unescapedTagEndLength
                    let token = TemplateToken(
                        type: .unescapedVariable(content: content, tagDelimiterPair: currentDelimiters.tagDelimiterPair),
                        lineNumber: startLineNumber,
                        templateID: templateID,
                        templateString: templateString,
                        utf8StartIndex: startIndex,
                        utf8EndIndex: tokenEndIndex)
                    if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                        return
                    }
                    state = .start
                    i += currentDelimiters.unescapedTagEndLength - 1
                }
            case .setDelimitersTag(let startIndex, let startLineNumber):
                if c == Self.newlineUtf8 {
                    lineNumber += 1
                } else if isAt(i, bytes: currentDelimiters.setDelimitersEndBytes, in: utf8Array) {
                    let tagInitialIndex = startIndex + currentDelimiters.setDelimitersStartLength
                    let contentData = Data(utf8Array[tagInitialIndex..<i])
                    let content = String(data: contentData, encoding: .utf8)!
                    let newDelimiters = content.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { $0.count > 0 }
                    if (newDelimiters.count != 2) {
                        let error = MustacheError(kind: .parseError, message: "Invalid set delimiters tag", templateID: templateID, lineNumber: startLineNumber)
                        tokenConsumer.parser(self, didFailWithError: error)
                        return;
                    }

                    let tokenEndIndex = i + currentDelimiters.setDelimitersEndLength
                    let token = TemplateToken(
                        type: .setDelimiters,
                        lineNumber: startLineNumber,
                        templateID: templateID,
                        templateString: templateString,
                        utf8StartIndex: startIndex,
                        utf8EndIndex: tokenEndIndex)
                    if !tokenConsumer.parser(self, shouldContinueAfterParsingToken: token) {
                        return
                    }

                    state = .start
                    i += currentDelimiters.setDelimitersEndLength - 1
                    currentDelimiters = ParserTagDelimiters(tagDelimiterPair: (newDelimiters[0], newDelimiters[1]))
                }
            }

            i += 1
        }


        // EOF

        switch state {
        case .start:
            break
        case .text(let startIndex, let startLineNumber):
            let textData = Data(utf8Array[startIndex..<count])
            let text = String(data: textData, encoding: .utf8)!
            let token = TemplateToken(
                type: .text(text: text),
                lineNumber: startLineNumber,
                templateID: templateID,
                templateString: templateString,
                utf8StartIndex: startIndex,
                utf8EndIndex: count)
            _ = tokenConsumer.parser(self, shouldContinueAfterParsingToken: token)
        case .tag(_, let startLineNumber):
            let error = MustacheError(kind: .parseError, message: "Unclosed Mustache tag", templateID: templateID, lineNumber: startLineNumber)
            tokenConsumer.parser(self, didFailWithError: error)
        case .unescapedTag(_, let startLineNumber):
            let error = MustacheError(kind: .parseError, message: "Unclosed Mustache tag", templateID: templateID, lineNumber: startLineNumber)
            tokenConsumer.parser(self, didFailWithError: error)
        case .setDelimitersTag(_, let startLineNumber):
            let error = MustacheError(kind: .parseError, message: "Unclosed Mustache tag", templateID: templateID, lineNumber: startLineNumber)
            tokenConsumer.parser(self, didFailWithError: error)
        }
    }

    private func isAt(_ index: Int, bytes: [UInt8]?, in utf8Array: [UInt8]) -> Bool {
        guard let bytes = bytes else {
            return false
        }
        guard index + bytes.count <= utf8Array.count else {
            return false
        }
        for i in 0..<bytes.count {
            if utf8Array[index + i] != bytes[i] {
                return false
            }
        }
        return true
    }

    // MARK: - Private

    fileprivate enum State {
        case start
        case text(startIndex: Int, startLineNumber: Int)
        case tag(startIndex: Int, startLineNumber: Int)
        case unescapedTag(startIndex: Int, startLineNumber: Int)
        case setDelimitersTag(startIndex: Int, startLineNumber: Int)
    }

    fileprivate struct ParserTagDelimiters {
        let tagDelimiterPair : TagDelimiterPair
        let tagStartLength: Int
        let tagEndLength: Int
        let tagStartBytes: [UInt8]
        let tagEndBytes: [UInt8]
        let unescapedTagStart: String?
        let unescapedTagStartLength: Int
        let unescapedTagStartBytes: [UInt8]?
        let unescapedTagEnd: String?
        let unescapedTagEndLength: Int
        let unescapedTagEndBytes: [UInt8]?
        let setDelimitersStart: String
        let setDelimitersStartLength: Int
        let setDelimitersStartBytes: [UInt8]
        let setDelimitersEnd: String
        let setDelimitersEndLength: Int
        let setDelimitersEndBytes: [UInt8]

        init(tagDelimiterPair : TagDelimiterPair) {
            self.tagDelimiterPair = tagDelimiterPair

            tagStartLength = tagDelimiterPair.0.utf8.count
            tagEndLength = tagDelimiterPair.1.utf8.count
            tagStartBytes = Array(tagDelimiterPair.0.utf8)
            tagEndBytes = Array(tagDelimiterPair.1.utf8)

            let usesStandardDelimiters = (tagDelimiterPair.0 == "{{") && (tagDelimiterPair.1 == "}}")
            unescapedTagStart = usesStandardDelimiters ? "{{{" : nil
            unescapedTagStartLength = unescapedTagStart?.utf8.count ?? 0
            unescapedTagStartBytes = unescapedTagStart != nil ? Array(unescapedTagStart!.utf8) : nil
            unescapedTagEnd = usesStandardDelimiters ? "}}}" : nil
            unescapedTagEndLength = unescapedTagEnd?.utf8.count ?? 0
            unescapedTagEndBytes = unescapedTagEnd != nil ? Array(unescapedTagEnd!.utf8) : nil

            setDelimitersStart = "\(tagDelimiterPair.0)="
            setDelimitersStartLength = setDelimitersStart.utf8.count
            setDelimitersStartBytes = Array(setDelimitersStart.utf8)
            setDelimitersEnd = "=\(tagDelimiterPair.1)"
            setDelimitersEndLength = setDelimitersEnd.utf8.count
            setDelimitersEndBytes = Array(setDelimitersEnd.utf8)
        }
    }
}

