import SwiftUI

// MARK: - Scout Stories Bar
/// Instagram-style horizontal scrollable stories bar
struct ScoutStoriesBar: View {
    @ObservedObject var store = ScoutStoryStore.shared
    @ObservedObject private var market = MarketViewModel.shared
    @State private var showingStoryDetail = false
    @State private var frozenStories: [ScoutStory] = [] // Snapshot for detail view
    @State private var frozenIndex: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                    )
                Text("Scout Keşifleri")
                    .font(.subheadline)
                    .bold()
                
                if store.unviewedCount > 0 {
                    Text("\(store.unviewedCount) yeni")
                        .font(.caption2)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.red)
                        )
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Stories Ring
            if store.stories.isEmpty {
                emptyState
            } else {
                storiesScroll
            }
        }
        .fullScreenCover(isPresented: $showingStoryDetail) {
            // Use frozen snapshot to prevent flickering
            if !frozenStories.isEmpty {
                ScoutStoryDetailView(
                    stories: frozenStories,
                    startIndex: frozenIndex,
                    onDismiss: { showingStoryDetail = false },
                    onAddToWatchlist: { symbol in
                        market.addToWatchlist(symbol: symbol)
                    },
                    onGoToDetail: { symbol in
                        showingStoryDetail = false
                    }
                )
            }
        }
    }
    
    // MARK: - Stories Scroll
    
    private var storiesScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(store.stories) { story in
                    StoryRingButton(story: story) {
                        // Freeze the stories before presenting
                        frozenStories = store.stories
                        if let idx = store.stories.firstIndex(where: { $0.id == story.id }) {
                            frozenIndex = idx
                        } else {
                            frozenIndex = 0
                        }
                        
                        // SAFE PRESENTATION: Dispatch async to allow state update to propagate
                        DispatchQueue.main.async {
                            showingStoryDetail = true
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .frame(height: 90)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundColor(DesignTokens.Colors.textTertiary)
                Text("Henüz keşif yok")
                    .font(.caption)
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            .padding(.vertical, 20)
            Spacer()
        }
    }
}

// MARK: - Story Ring Button
/// Individual story avatar with animated ring
struct StoryRingButton: View {
    let story: ScoutStory
    let action: () -> Void
    
    @State private var isPulsing = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Avatar with ring
                ZStack {
                    // Ring
                    Circle()
                        .stroke(
                            story.isViewed ?
                            LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [.red, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 3
                        )
                        .frame(width: 64, height: 64)
                        .scaleEffect(isPulsing && !story.isViewed ? 1.08 : 1.0)
                    
                    // Inner circle with symbol
                    Circle()
                        .fill(DesignTokens.Colors.surface)
                        .frame(width: 56, height: 56)
                    
                    // Symbol text
                    Text(story.symbol.prefix(4))
                        .font(DesignTokens.Fonts.custom(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    // Score badge
                    ZStack {
                        Circle()
                            .fill(story.signalColor)
                            .frame(width: 22, height: 22)
                        
                        Text(String(format: "%.0f", story.orionScore))
                            .font(DesignTokens.Fonts.custom(size: 9, weight: .bold))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                    }
                    .offset(x: 22, y: 22)
                }
                
                // Price change
                Text(String(format: "%+.1f%%", story.changePercent))
                    .font(DesignTokens.Fonts.custom(size: 10, weight: .medium))
                    .foregroundColor(story.changePercent >= 0 ? .green : .red)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .onAppear {
            if !story.isViewed {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Preview
#Preview {
    VStack {
        ScoutStoriesBar()
        Spacer()
    }
    .background(DesignTokens.Colors.background)
}
