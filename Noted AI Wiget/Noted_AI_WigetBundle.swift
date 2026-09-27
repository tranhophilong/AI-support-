//
//  Noted_AI_WigetBundle.swift
//  Noted AI Wiget
//
//  Created by Long Tran on 20/9/26.
//

import WidgetKit
import SwiftUI

@main
struct Noted_AI_WigetBundle: WidgetBundle {
    var body: some Widget {
        Noted_AI_Wiget()
        Noted_AI_WigetControl()
        Noted_AI_WigetLiveActivity()
    }
}
