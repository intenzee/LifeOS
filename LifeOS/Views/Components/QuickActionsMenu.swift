import SwiftUI

struct QuickActionsMenu: View {
    @Binding var isPresented: Bool
    let onAction: (QuickActionType) -> Void

    private let quickActions: [(title: String, systemImage: String, action: QuickActionType)] = [
        ("Breakfast", "sunrise.fill", .breakfast),
        ("Lunch", "fork.knife", .lunch),
        ("Dinner", "moon.stars.fill", .dinner),
        ("Snacks", "takeoutbag.and.cup.and.straw.fill", .snacks),
        ("Exercise", "figure.walk", .exercise),
        ("Water", "drop.fill", .water),
        ("Weight", "scalemass.fill", .weight),
        ("Barcode", "barcode.viewfinder", .barcodeScan),
        ("AI Meal", "sparkles", .aiMealScan)
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 18) {
                HStack {
                    Text("Quick Actions")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(quickActions, id: \.title) { item in
                        Button(action: {
                            onAction(item.action)
                            isPresented = false
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: item.systemImage)
                                    .font(.headline)
                                Text(item.title)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 84)
                            .foregroundColor(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(red: 0.14, green: 0.14, blue: 0.16))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.blue.opacity(0.25), lineWidth: 1)
                            )
                        }
                    }
                }

                Button(action: {
                    isPresented = false
                }) {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.14, green: 0.14, blue: 0.16))
                        )
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.blue.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
    }
}