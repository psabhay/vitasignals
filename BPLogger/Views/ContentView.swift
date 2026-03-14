import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "heart.text.square")
                }
                .tag(0)

            ReadingsListView()
                .tabItem {
                    Label("History", systemImage: "list.bullet.clipboard")
                }
                .tag(1)

            ChartsContainerView()
                .tabItem {
                    Label("Charts", systemImage: "chart.xyaxis.line")
                }
                .tag(2)
        }
        .tint(Color.accentColor)
    }
}
