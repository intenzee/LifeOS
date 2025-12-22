import SwiftUI

struct ContentView: View {
    
    @State private var waterCount: Int = 0
    @State private var showWaterPicker: Bool = false
    
    // Dummy calorie data (wire real data later)
    let caloriesConsumed: Double = 1450
    let caloriesLimit: Double = 2200
    
    var body: some View {
        ZStack {
            // Background
            Color(red: 0.06, green: 0.06, blue: 0.07)
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                
                // Header
                HStack {
                    Text("Today")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.top, 20)
                
                // Daily Progress Card
                DashboardCard(
                    title: "Daily Progress",
                    subtitle: "Overview of your day",
                    glowStrength: 0.35
                )
                
                // Floating Calories Ring
                CaloriesRing(
                    consumed: caloriesConsumed,
                    limit: caloriesLimit
                )
                
                // Water Card
                DashboardCard(
                    title: "Water Intake",
                    subtitle: "\(waterCount) / 8 glasses",
                    glowStrength: 0.7
                )
                .onTapGesture {
                    if waterCount < 12 {
                        waterCount += 1
                    }
                }
                .onLongPressGesture(minimumDuration: 0.15) {
                    showWaterPicker = true
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Water Picker Overlay
            if showWaterPicker {
                WaterPickerView(
                    waterCount: $waterCount,
                    isPresented: $showWaterPicker
                )
                .transition(.opacity)
                .scaleEffect(showWaterPicker ? 1.0 : 0.96)
            }
        }
        .animation(.easeOut(duration: 0.4), value: showWaterPicker)
    }
}

struct CaloriesRing: View {
    
    let consumed: Double
    let limit: Double
    
    var progress: Double {
        min(consumed / limit, 1.0)
    }
    
    var body: some View {
        ZStack {
            // Ring background
            Circle()
                .stroke(Color.blue.opacity(0.15), lineWidth: 16)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.blue,
                    style: StrokeStyle(
                        lineWidth: 16,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
            
            // Center Text
            VStack(spacing: 6) {
                Text("Calorie Budget")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("\(Int(consumed))")
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("/ \(Int(limit)) kcal")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 150, height: 150)
        .shadow(color: Color.blue.opacity(0.6),
                radius: 20,
                x: 0,
                y: 0)
        .padding(.vertical, 8)
    }
}

struct DashboardCard: View {
    let title: String
    let subtitle: String
    let glowStrength: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: Color.blue.opacity(glowStrength),
                radius: 12,
                x: 0,
                y: 0)
    }
}

struct WaterPickerView: View {
    
    @Binding var waterCount: Int
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 24) {
                
                Text("Water Intake")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Picker("", selection: $waterCount) {
                    ForEach(0...12, id: \.self) { value in
                        Text("\(value) glasses")
                            .foregroundColor(.white)
                    }
                }
                .pickerStyle(.wheel)
                
                Button(action: {
                    isPresented = false
                }) {
                    Text("Done")
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .shadow(color: Color.blue.opacity(0.6),
                    radius: 20,
                    x: 0,
                    y: 0)
            .padding(.horizontal, 24)
        }
    }
}
