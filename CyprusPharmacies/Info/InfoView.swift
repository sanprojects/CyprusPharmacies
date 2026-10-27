//
//  InfoView.swift
//  CyprusPharmacies
//

import SwiftUI

struct InfoView: View {
    static let ministryURL = URL(string: "https://www.moh.gov.cy/moh/phs/phs.nsf/All/091BC51661367EE1C225857B002F972D?OpenDocument")!

    private static let paragraphs = [
        "The location of pharmacies on the map was obtained by automatic search on the Google map. We recommend you to clarify the location on the map or check with the pharmacist before the trip.",
        "Each pharmacy on the list will be open from 8 am to 11 pm, including weekends and public holidays.",
        "In addition, the pharmacist on duty will be available to carry out any prescription after the pharmacy closes - from 11 pm to 8 am the next day. You can call the listed numbers to contact a pharmacist to fulfil a prescription.",
        "If a duty pharmacist does not have the medicines necessary to fulfil the prescription, he/she must write on the prescription the words “Medicines that are not available” and sign, indicating the day and time.",
    ]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Self.paragraphs, id: \.self) { Text($0) }
                    Link(destination: Self.ministryURL) {
                        Label("For more information", systemImage: "safari")
                            .font(.headline)
                    }
                    .padding(.top, 4)
                }
                .padding(Margin.content)
            }
            .navigationTitle("Duty pharmacies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // The system's round X on iOS 26+; the same round face as the other sheets before.
                    if #available(iOS 26, *) {
                        Button(role: .close) { dismiss() }
                    } else {
                        Button { dismiss() } label: { CircleButtonLabel(systemImage: "xmark") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                    }
                }
            }
        }
    }
}
