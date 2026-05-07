import Foundation

struct ExportService {
    let exportsDirectoryURL: URL

    func exportJSON(records: [RecordEvent], baseName: String = "records") throws -> URL {
        try FileManager.default.createDirectory(at: exportsDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        let targetURL = defaultURL(baseName: baseName, extension: "json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(records)

        do {
            try data.write(to: targetURL, options: .atomic)
            return targetURL
        } catch {
            throw StoreError.writeFailed(targetURL)
        }
    }

    func exportExcel(records: [RecordEvent], baseName: String = "records") throws -> URL {
        try FileManager.default.createDirectory(at: exportsDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        let targetURL = defaultURL(baseName: baseName, extension: "xlsx")
        let stagingDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("state-switch-xlsx-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: stagingDirectoryURL)
        }

        do {
            try FileManager.default.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            try writeXLSXStructure(records: records, to: stagingDirectoryURL)

            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = stagingDirectoryURL
            process.arguments = ["-qr", targetURL.path, "."]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw StoreError.exportFailed("Excel 导出失败。")
            }

            return targetURL
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.exportFailed("Excel 导出失败。")
        }
    }

    private func writeXLSXStructure(records: [RecordEvent], to directoryURL: URL) throws {
        let relsURL = directoryURL.appendingPathComponent("_rels", isDirectory: true)
        let xlURL = directoryURL.appendingPathComponent("xl", isDirectory: true)
        let xlRelsURL = xlURL.appendingPathComponent("_rels", isDirectory: true)
        let worksheetsURL = xlURL.appendingPathComponent("worksheets", isDirectory: true)

        try FileManager.default.createDirectory(at: relsURL, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: xlRelsURL, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: worksheetsURL, withIntermediateDirectories: true, attributes: nil)

        let files: [(String, URL)] = [
            (contentTypesXML, directoryURL.appendingPathComponent("[Content_Types].xml")),
            (rootRelationshipsXML, relsURL.appendingPathComponent(".rels")),
            (workbookXML, xlURL.appendingPathComponent("workbook.xml")),
            (workbookRelationshipsXML, xlRelsURL.appendingPathComponent("workbook.xml.rels")),
            (stylesXML, xlURL.appendingPathComponent("styles.xml")),
            (worksheetXML(records: records), worksheetsURL.appendingPathComponent("sheet1.xml")),
        ]

        for (content, url) in files {
            guard let data = content.data(using: .utf8) else {
                throw StoreError.writeFailed(url)
            }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw StoreError.writeFailed(url)
            }
        }
    }

    private func worksheetXML(records: [RecordEvent]) -> String {
        let headers = [
            "id",
            "recorded_at",
            "previous_state",
            "previous_state_code",
            "current_state",
            "state_code",
            "app_name",
            "app_bundle_id",
            "date",
            "source",
            "source_detail",
            "created_at",
        ]

        let rows = [headers] + records.map {
            [
                $0.id,
                $0.recordedAt,
                $0.previousState ?? "",
                $0.previousStateCode ?? "",
                $0.currentState,
                $0.stateCode,
                $0.appName ?? "",
                $0.appBundleIdentifier ?? "",
                $0.date,
                $0.source,
                $0.sourceDetail ?? "",
                $0.createdAt,
            ]
        }

        let columnWidths = [26, 30, 18, 20, 18, 20, 18, 28, 14, 16, 42, 30]
            .enumerated()
            .map { index, width in
                "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
            }
            .joined()

        let sheetRows = rows.enumerated().map { rowIndex, values in
            let cells = values.enumerated().map { columnIndex, value in
                let reference = "\(excelColumnName(for: columnIndex + 1))\(rowIndex + 1)"
                let style = rowIndex == 0 ? " s=\"1\"" : ""
                return "<c r=\"\(reference)\" t=\"inlineStr\"\(style)><is><t>\(escapeXML(value))</t></is></c>"
            }.joined()
            return "<row r=\"\(rowIndex + 1)\">\(cells)</row>"
        }.joined()

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <cols>\(columnWidths)</cols>
          <sheetData>\(sheetRows)</sheetData>
        </worksheet>
        """
    }

    private var contentTypesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
    }

    private var rootRelationshipsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
    }

    private var workbookXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="records" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
    }

    private var workbookRelationshipsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
    }

    private var stylesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="2">
            <font>
              <sz val="11"/>
              <name val="Aptos"/>
            </font>
            <font>
              <b/>
              <sz val="11"/>
              <name val="Aptos"/>
            </font>
          </fonts>
          <fills count="2">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
          </fills>
          <borders count="1">
            <border>
              <left/>
              <right/>
              <top/>
              <bottom/>
              <diagonal/>
            </border>
          </borders>
          <cellStyleXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          </cellStyleXfs>
          <cellXfs count="2">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
          </cellXfs>
          <cellStyles count="1">
            <cellStyle name="Normal" xfId="0" builtinId="0"/>
          </cellStyles>
        </styleSheet>
        """
    }

    private func defaultURL(baseName: String, extension suffix: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = formatter.string(from: Date())
        return exportsDirectoryURL.appendingPathComponent("\(baseName)_\(stamp).\(suffix)")
    }

    private func excelColumnName(for index: Int) -> String {
        var dividend = index
        var name = ""
        while dividend > 0 {
            let modulo = (dividend - 1) % 26
            name = String(UnicodeScalar(65 + modulo)!) + name
            dividend = (dividend - modulo) / 26
        }
        return name
    }

    private func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
