import SwiftUI

struct ContentView: View {
    
    @State private var waterCount: Int = 0
    @State private var showWaterPicker: Bool = false
    
    let caloriesConsumed: Double = 1450
    let caloriesLimit: Double = 2200
    
    var body: some View {
        ZStack {
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
                
                // 🔷 DAILY PROGRESS CONTAINER
                DailyProgressContainer(waterCount: waterCount)
                
                // Floating Calories Ring
                CaloriesRing(
                    consumed: caloriesConsumed,
                    limit: caloriesLimit
                )
                
                // Water Card (detailed)
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

// MARK: - Daily Progress Container
struct DailyProgressContainer: View {
    
    let waterCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            Text("Daily Progress")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                
                // ROW 1
                HStack(spacing: 12) {
                    TodoLineChartCard()
                    WeightProgressCard()
                }
                
                // ROW 2
                HStack(spacing: 12) {
                    GymIntensityCard()
                    MoodScaleCard()
                }
                
                // ROW 3
                HStack(spacing: 12) {
                    WaterSummaryCard(waterCount: waterCount)
                    FoodQualityCard()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.blue.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: Color.blue.opacity(0.4),
                radius: 14,
                x: 0,
                y: 0)
    }
}

// MARK: - Mini Card: To-Do Line Chart
struct TodoLineChartCard: View {
    
    let dummyData: [CGFloat] = [2, 4, 3, 5, 4, 6, 5]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To‑Do")
                .font(.caption)
                .foregroundColor(.gray)
            
            GeometryReader { geo in
                Path { path in
                    for index in dummyData.indices {
                        let x = geo.size.width / CGFloat(dummyData.count - 1) * CGFloat(index)
                        let y = geo.size.height - (dummyData[index] / 6 * geo.size.height)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.blue, lineWidth: 2)
            }
            .frame(height: 50)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
        )
    }
}

// MARK: - Mini Card: Weight Progress
struct WeightProgressCard: View {
    
    let currentWeight: Double = 72.5
    let targetWeight: Double = 68.0
    
    var difference: Double {
        currentWeight - targetWeight
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weight")
                .font(.caption)
                .foregroundColor(.gray)
            
            Text("\(currentWeight, specifier: "%.1f") kg")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(difference > 0 ?
                 "\(difference, specifier: "%.1f") kg to go" :
                 "Goal reached")
                .font(.caption)
                .foregroundColor(difference > 0 ? .orange : .green)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
        )
    }
}

// MARK: - Mini Card: Gym Intensity
struct GymIntensityCard: View {
    
    let intensity: String = "High"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gym")
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(intensity)
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 4) {
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 12, height: 6)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
        )
    }
}

// MARK: - Mini Card: Mood Scale
struct MoodScaleCard: View {
    
    let mood: String = "😊"
    let label: String = "Good"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mood")
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(mood)
                .font(.largeTitle)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.green)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
        )
    }
}

// MARK: - Mini Card: Water Summary
struct WaterSummaryCard: View {
    
    let waterCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Water")
                .font(.caption)
                .foregroundColor(.gray)
            
            Text("\(waterCount) / 8")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("glasses")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
        )
    }
}

// MARK: - Mini Card: Food Quality
struct FoodQualityCard: View {
    
    let highProtein: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Food")
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(highProtein ? "High Protein" : "Low Protein")
                .font(.headline)
                .foregroundColor(highProtein ? .green : .orange)
            
            Text("Mess")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
        )
    }
}

// MARK: - Calories Ring
struct CaloriesRing: View {
    
    let consumed: Double
    let limit: Double
    
    var progress: Double {
        min(consumed / limit, 1.0)
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.blue.opacity(0.15), lineWidth: 16)
            
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

// MARK: - Dashboard Card
struct DashboardCard: View {
    let title: String
    let subtitle: String
    let glowStrength: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.gray)
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

// MARK: - Water Picker
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
                
                Button("Done") {
                    isPresented = false
                }
                .fontWeight(.semibold)
                .foregroundColor(.black)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(12)
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
