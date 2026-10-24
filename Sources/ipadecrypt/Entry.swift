import Darwin
import Foundation

@main
struct IPADecrypt {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.contains("--help") || arguments.contains("-h") {
                print(Options.usage)
                return
            }
            let options = try Options(arguments)
            let output = try options.run(home: FileManager.default.homeDirectoryForCurrentUser) {
                FileHandle.standardError.write(Data("Path to credential.bin: ".utf8))
                return readLine()
            }
            print("Decrypted: \(output.path)")
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
