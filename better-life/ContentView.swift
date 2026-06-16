import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: HabitStore?

    var body: some View {
        Group {
            if let store {
                TabView {
                    TodayView(store: store)
                        .tabItem {
                            Label("今日", systemImage: "checkmark.circle")
                        }

                    StudyView()
                        .tabItem {
                            Label("学习", systemImage: "timer")
                        }

                    VocabView()
                        .tabItem {
                            Label("背单词", systemImage: "character.book.closed")
                        }

                    HistoryView(store: store)
                        .tabItem {
                            Label("历史", systemImage: "calendar")
                        }
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if store == nil {
                store = HabitStore(modelContext: modelContext)
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                store?.checkDateChange()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: DailyRecord.self, inMemory: true)
}
