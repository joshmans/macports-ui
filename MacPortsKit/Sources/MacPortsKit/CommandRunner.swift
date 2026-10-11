//
//  CommandRunner.swift
//  MacPortsKit
//

import Foundation

/// Runs command line tools synchronously. Must not be called on the main thread.
enum CommandRunner {
	
	struct Result {
		let status: Int32
		let output: String
	}
	
	static func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) -> Result {
		assert(!Thread.isMainThread, "Must not be called on main thread.")
		
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
		
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		
		do {
			try process.run()
		} catch {
			return Result(status: -1, output: error.localizedDescription)
		}
		
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
	}
	
	/// Runs a shell command as administrator, showing the standard macOS authentication dialog.
	static func runAsAdministrator(_ executable: String, _ arguments: [String]) -> Result {
		let command = ([executable] + arguments).map(shellQuote).joined(separator: " ")
		let script = "do shell script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
		return run("/usr/bin/osascript", ["-e", script])
	}
	
	/// Quotes the given string for safe use in a POSIX shell.
	static func shellQuote(_ string: String) -> String {
		"'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
	
}

/// Information about the machine the app runs on.
enum SystemInfo {
	
	static var isARM: Bool { machine == "arm64" }
	
	static var machine: String {
		var info = utsname()
		uname(&info)
		return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
	}
	
	/// The Darwin kernel major version, which MacPorts uses in archive names (25 for macOS 26).
	static var darwinMajor: Int {
		var info = utsname()
		uname(&info)
		let release = withUnsafeBytes(of: &info.release) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
		return Int(release.split(separator: ".").first ?? "") ?? 0
	}
	
}
