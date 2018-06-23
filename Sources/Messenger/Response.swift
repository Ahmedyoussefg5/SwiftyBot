//
//  Response.swift
//  SwiftyBot
//
//  The MIT License (MIT)
//
//  Copyright (c) 2016 - 2018 Fabrizio Brancati.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import BFKit
import Foundation
import Helpers
import Vapor

/// Messenger response.
public struct Response: Content {
    /// Message type.
    public enum MessagingType: String, Codable {
        /// Resposne type.
        case response = "RESPONSE"
    }
    
    /// Messaging type.
    private(set) public var messagingType: MessagingType
    /// Recipient.
    public var recipient: Recipient?
    /// Final response message.
    public var message: MessageResponse
    
    /// Coding keys, used by Codable protocol.
    private enum CodingKeys: String, CodingKey {
        case messagingType = "messaging_type"
        case recipient
        case message
    }
    
    /// Create a response for a request.
    ///
    /// - Parameter request: Message request.
    /// - Returns: Returns the message `HTTPResponse`.
    /// - Throws: Decoding errors.
    public func response(_ request: Request) throws -> HTTPResponse {
        /// Decode the response.
        let pageResponse = try request.content.syncDecode(PageRequest.self)
        /// Check that the request comes from a "page".
        guard pageResponse.object == "page" else {
            /// Throw an abort response, with a custom message.
            throw Abort(.badRequest, reason: "Message not generated by a page.")
        }
        
        /// Creates the initial response.
        var response = Response(messagingType: .response, recipient: nil, message: .text("Unknown error."))
        
        /// For each entry in the response.
        for entry in pageResponse.entries {
            /// For each event in the entry.
            for event in entry.messages {
                /// Mark the message as seen.
                SenderAction(id: event.sender.id, action: .markSeen, on: request)
                
                /// If it's a postback action.
                if let postback = event.postback {
                    response.message = .text(postback.payload ?? "No payload provided by developer.")
                /// If it's a normal message.
                } else if let message = event.message {
                    /// Check if the message is empty.
                    if message.text.isEmpty {
                        response.message = .text("I'm sorry but your message is empty 😢")
                    /// Check if the message has greetings.
                    } else if message.text.hasGreetings() {
                        var greeting = "Hi!"
                        if let userInfo = UserInfo(id: event.sender.id, on: request) {
                            greeting = "Hi \(userInfo.firstName)!"
                        }
                        
                        /// Set the response message.
                        response.message = .text("""
                        \(greeting)
                        This is an example on how to create a bot with Swift.
                        If you want to see more try to send me "buy", "sell" or "shop".
                        """)
                    /// Check if the message has "sell", "buy" or "shop" in its text.
                    } else if message.text.lowercased().contains("sell") || message.text.lowercased().contains("buy") || message.text.lowercased().contains("shop") {
                        /// Create the elements array and add all the created elements.
                        var elements: [Element] = []
                        /// Add Queuer element.
                        elements.append(Element.queuer)
                        /// Add BFKit-Swift element.
                        elements.append(Element.bfkitSwift)
                        /// Add BFKit element.
                        elements.append(Element.bfkit)
                        /// Add SwiftyBot element.
                        elements.append(Element.swiftyBot)
                        
                        /// Creates the payload.
                        let payload = Payload(templateType: .generic, elements: elements)
                        /// Creates the attachment.
                        let attachment = Attachment(type: .template, payload: payload)
                        /// Finally creates the structured message.
                        let structuredMessage = StructuredMessage(attachment: attachment)
                        
                        response.message = .structured(structuredMessage)
                    /// It's a normal message, so reverse it.
                    } else {
                        response.message = .text(message.text.reversed(preserveFormat: true))
                    }
                /// If the message doent's exist.
                } else if event.message == nil {
                    response.message = .text("Webhook received unknown event.")
                }
                
                /// Set the recipient with the sender ID.
                response.recipient = Recipient(id: event.sender.id)
                
                /// Sende the response to the Facebook Messenger APIs.
                _ = try request.client().post("https://graph.facebook.com/\(messengerAPIVersion)/me/messages?access_token=\(messengerToken)", headers: ["Content-Type": "application/json"]) { messageRequest in
                    try messageRequest.content.encode(response)
                }
            }
        }
        
        /// Sending an HTTP 200 OK response is required.
        /// https://developers.facebook.com/docs/messenger-platform/webhook#response
        var httpResponse = HTTPResponse(status: .ok, headers: ["Content-Type": "application/json"])
        /// Encode the response.
        try JSONEncoder().encode(response, to: &httpResponse, on: request.eventLoop)
        return httpResponse
    }
}

// MARK: - Response Extension

/// Response extension.
public extension Response {
    /// Empty init method.
    /// Declared in an extension to not override default `init` function.
    public init() {
        messagingType = .response
        recipient = nil
        message = .text("")
    }
}
