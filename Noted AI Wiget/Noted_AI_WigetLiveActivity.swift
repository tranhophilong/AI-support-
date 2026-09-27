//
//  Noted_AI_WigetLiveActivity.swift
//  Noted AI Wiget
//
//  Created by Long Tran on 20/9/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct Noted_AI_WigetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct Noted_AI_WigetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Noted_AI_WigetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension Noted_AI_WigetAttributes {
    fileprivate static var preview: Noted_AI_WigetAttributes {
        Noted_AI_WigetAttributes(name: "World")
    }
}

extension Noted_AI_WigetAttributes.ContentState {
    fileprivate static var smiley: Noted_AI_WigetAttributes.ContentState {
        Noted_AI_WigetAttributes.ContentState(emoji: "😀")
     }

     fileprivate static var starEyes: Noted_AI_WigetAttributes.ContentState {
         Noted_AI_WigetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: Noted_AI_WigetAttributes.preview) {
   Noted_AI_WigetLiveActivity()
} contentStates: {
    Noted_AI_WigetAttributes.ContentState.smiley
    Noted_AI_WigetAttributes.ContentState.starEyes
}
