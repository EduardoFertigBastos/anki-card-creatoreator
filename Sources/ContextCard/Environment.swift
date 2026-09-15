import Foundation

enum Environment {
    static func value(for key: String) -> String? {
        if let processValue = ProcessInfo.processInfo.environment[key], !processValue.isEmpty {
            return processValue
        }

        let startingDirectories = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            Bundle.main.bundleURL
        ]

        for startingDirectory in startingDirectories {
            var directory = startingDirectory
            for _ in 0..<7 {
                let fileURL = directory.appendingPathComponent(".env")
                if let contents = try? String(contentsOf: fileURL, encoding: .utf8),
                   let value = parse(contents: contents, key: key),
                   !value.isEmpty {
                    return value
                }
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path { break }
                directory = parent
            }
        }
        return nil
    }

    private static func parse(contents: String, key: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            guard name == key else { continue }
            var value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, ((value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'")) {
                value.removeFirst()
                value.removeLast()
            }
            return value
        }
        return nil
    }
}
