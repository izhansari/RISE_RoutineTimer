//
//  FontHelpers.swift
//  RISE_RoutineTimer
//
//  Mirrors the font setup from TwoMinRuleTimer.
//

import CoreGraphics
import SwiftUI

func analogFont(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
    .custom("FakeReceipt-Regular", size: size)
}

func digitFont(_ size: CGFloat) -> Font {
    .custom("FakeReceipt-Regular", size: size)
}
