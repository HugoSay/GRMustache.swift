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


struct TemplateToken {
    enum `Type` {
        /// text
        case text(text: String)

        /// {{ content }}
        case escapedVariable(content: String, tagDelimiterPair: TagDelimiterPair)

        /// {{{ content }}}
        case unescapedVariable(content: String, tagDelimiterPair: TagDelimiterPair)

        /// {{! comment }}
        case comment

        /// {{# content }}
        case section(content: String, tagDelimiterPair: TagDelimiterPair)

        /// {{^ content }}
        case invertedSection(content: String, tagDelimiterPair: TagDelimiterPair)

        /// {{/ content }}
        case close(content: String)

        /// {{> content }}
        case partial(content: String)

        /// {{= ... ... =}}
        case setDelimiters

        /// {{% content }}
        case pragma(content: String)

        /// {{< content }}
        case partialOverride(content: String)

        /// {{$ content }}
        case block(content: String)
    }

    let type: Type
    let lineNumber: Int
    let templateID: TemplateID?
    let templateString: String

    // Store UTF-8 indices instead of expensive String range
    private let utf8StartIndex: Int
    private let utf8EndIndex: Int

    // Lazily computed String range - only calculated when actually needed
    var range: Range<String.Index> {
        let utf8View = templateString.utf8
        let startIndex = utf8View.index(utf8View.startIndex, offsetBy: utf8StartIndex)
        let endIndex = utf8View.index(utf8View.startIndex, offsetBy: utf8EndIndex)
        return Range(uncheckedBounds: (String.Index(startIndex, within: templateString)!, String.Index(endIndex, within: templateString)!))
    }

    var templateSubstring: String { return String(templateString[range]) }

    // New convenience initializer that takes UTF-8 indices
    init(type: Type, lineNumber: Int, templateID: TemplateID?, templateString: String, utf8StartIndex: Int, utf8EndIndex: Int) {
        self.type = type
        self.lineNumber = lineNumber
        self.templateID = templateID
        self.templateString = templateString
        self.utf8StartIndex = utf8StartIndex
        self.utf8EndIndex = utf8EndIndex
    }

    // Legacy initializer for backward compatibility
    init(type: Type, lineNumber: Int, templateID: TemplateID?, templateString: String, range: Range<String.Index>) {
        self.type = type
        self.lineNumber = lineNumber
        self.templateID = templateID
        self.templateString = templateString

        // Convert String.Index to UTF-8 byte indices (expensive, but only done when using legacy init)
        let utf8View = templateString.utf8

        // Calculate UTF-8 byte offsets from string indices
        let startStringIndex = String.Index(range.lowerBound, within: templateString) ?? templateString.startIndex
        let endStringIndex = String.Index(range.upperBound, within: templateString) ?? templateString.endIndex

        let startUtf8Index = utf8View.index(utf8View.startIndex, offsetBy: templateString.distance(from: templateString.startIndex, to: startStringIndex))
        let endUtf8Index = utf8View.index(utf8View.startIndex, offsetBy: templateString.distance(from: templateString.startIndex, to: endStringIndex))

        self.utf8StartIndex = utf8View.distance(from: utf8View.startIndex, to: startUtf8Index)
        self.utf8EndIndex = utf8View.distance(from: utf8View.startIndex, to: endUtf8Index)
    }

    var tagDelimiterPair: TagDelimiterPair? {
        switch type {
        case .escapedVariable(content: _, tagDelimiterPair: let tagDelimiterPair):
            return tagDelimiterPair
        case .unescapedVariable(content: _, tagDelimiterPair: let tagDelimiterPair):
            return tagDelimiterPair
        case .section(content: _, tagDelimiterPair: let tagDelimiterPair):
            return tagDelimiterPair
        case .invertedSection(content: _, tagDelimiterPair: let tagDelimiterPair):
            return tagDelimiterPair
        default:
            return nil
        }
    }

    var locationDescription: String {
        if let templateID = templateID {
            return "line \(lineNumber) of template \(templateID)"
        } else {
            return "line \(lineNumber)"
        }
    }
}
