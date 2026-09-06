//
//  FontHelpers.swift
//  RISE_RoutineTimer
//
//  The "Fake Receipt" dot-matrix face is used for every routine label and
//  for the countdown digits.
//

import SwiftUI

func analogFont(_ size: CGFloat) -> Font {
    .custom("FakeReceipt-Regular", size: size)
}

func digitFont(_ size: CGFloat) -> Font {
    analogFont(size)
}
