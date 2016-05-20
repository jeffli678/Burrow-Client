//
//  ServerMessage.swift
//  Burrow
//
//  Created by Jaden Geller on 4/11/16.
//
//

import Logger
extension Logger { public static let serverMessageCategory = "SeverMessage" }
private let log = Logger.category(Logger.serverMessageCategory)

extension ServerMessage {
    /// The answers contained within the message.  Note that each answer is only
    /// valid while `self` exists, otherwise a segmentation fault may occur!
    var answers: LazyMapCollection<Range<Int32>, ResourceRecord> {
        return (0..<ServerMessageGetCount(self, ns_s_an)).lazy.map { index in
            var record = ResourceRecord()
            guard ServerMessageParse(self, ns_s_an, index, &record) == 0 else {
                fatalError("Unable to parse answer at index \(index).")
            }
            return record
        }
    }
}

extension ServerMessage {
    /// Queries `domain` for a record of the specifed class and type, and stores the
    /// result in a buffer of size `bufferSize`. Note that if the buffer is too small
    /// to hold the result, an exception will be thrown. The resulting message is
    /// returned in a `ManagedBuffer` object such that its `value` property is only
    /// valid when while the buffer exists, otherwise a segmentation fault may occur.

    static func withQuery(domain domain: Domain, recordClass: RecordClass, recordType: RecordType, useTCP: Bool, bufferSize: Int) throws -> ManagedBuffer<ServerMessage, UInt8> {
        log.info("Will attempt to query `\(domain)`")
        
        do {
            var status: Int = 0
            
            let result = ManagedBuffer<ServerMessage, UInt8>.create(bufferSize, initialValue: { buffer in
                var serverMessage = ServerMessage()
                status = buffer.withUnsafeMutablePointerToElements { bufferPointer in
                    String(domain).nulTerminatedUTF8.withUnsafeBufferPointer { domainBuffer in
                        Int(ServerMessageFromQuery(
                            UnsafePointer(domainBuffer.baseAddress),
                            recordClass,
                            recordType,
                            useTCP,
                            UnsafeMutablePointer(bufferPointer),
                            Int32(bufferSize),
                            &serverMessage
                        ))
                    }
                }
                return serverMessage
            })
            guard status == 0 else {
                throw NSError.netDBError() ?? NSError.posixError()
            }
            log.info("Successfully queried `\(domain)`")
            return result
        } catch let error as NSError where error.domain == "NetDBErrorDomain" && error.code == 2 {
            log.warning("Failed query for `\(domain)`; will retry...")

            // Try again!
            return try withQuery(domain: domain, recordClass: recordClass, recordType: recordType, useTCP: useTCP, bufferSize: bufferSize)
        }
    }
}
