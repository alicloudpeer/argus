import SwiftUI

/// V5 mockup dil bütünlüğü için in-place refactor.
/// 2026-04-22 Sprint 3 — üst chrome `ArgusNavHeader`'a alındı (bars3 holo deco,
/// menu + checkmark action, okunmamış sayısı status satırında). Row stili ve
/// sheet akışı (ArgusReportDetailView) korunur; `NotificationStore.shared`
/// veri imzası aynı.
struct NotificationsView: View {
    @ObservedObject var store = NotificationStore.shared
    @State private var selectedNotification: ArgusNotification?
    @ObservedObject private var market = MarketViewModel.shared
    var deepLinkID: String? = nil
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @EnvironmentObject private var router: NavigationRouter
    @Environment(\.dismiss) private var dismiss
    @State private var showDrawer = false

    private var isPushed: Bool { !router.navigationStack.isEmpty }

    private var unreadCount: Int {
        store.notifications.filter { !$0.isRead }.count
    }

    private var headerActions: [ArgusNavHeader.Action] {
        var list: [ArgusNavHeader.Action] = []
        if !isPushed {
            list.append(.menu({
                withAnimation(ArgusDrawerView.toggleAnimation) {
                    showDrawer = true
                }
            }))
        }
        if !store.notifications.isEmpty {
            list.append(.custom(sfSymbol: "checkmark.circle",
                                action: { store.markAllRead() }))
        }
        return list
    }

    private var headerStatus: ArgusNavHeader.Status {
        if store.notifications.isEmpty {
            return .custom(dotColor: DesignTokens.Colors.textTertiary,
                           label: "Hazır",
                           trailing: "Sinyal bekleniyor")
        }
        if unreadCount == 0 {
            return .custom(dotColor: InstitutionalTheme.Colors.aurora,
                           label: "Hepsi okundu",
                           trailing: "\(store.notifications.count) kayıt")
        }
        return .custom(dotColor: InstitutionalTheme.Colors.crimson,
                       label: "\(unreadCount) okunmamış",
                       trailing: "\(store.notifications.count) kayıt")
    }

    var body: some View {
        // 2026-05-03 H-59: nested NavigationStack kaldırıldı.
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                    ArgusNavHeader(
                        title: "Gelen kutusu",
                        subtitle: "Sinyal, uyarı, rapor",
                        leadingDeco: isPushed
                            ? .back(onTap: { dismiss() })
                            : .bars3([.holo, .text, .text]),
                        actions: headerActions,
                        status: headerStatus
                    )

                    if store.notifications.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "bell.slash")
                                .font(DesignTokens.Fonts.custom(size: 28))
                                .foregroundColor(DesignTokens.Colors.textTertiary)
                            VStack(spacing: 4) {
                                Text("Henüz bildirim yok")
                                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text("Arka planda fırsat aranıyor.")
                                    .font(DesignTokens.Fonts.custom(size: 12))
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(store.notifications) { note in
                                    NotificationRow(notification: note)
                                        .onTapGesture {
                                            selectedNotification = note
                                            store.markAsRead(note)
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
        }
        .onAppear {
            if let idString = deepLinkID, let id = UUID(uuidString: idString) {
                if let note = store.notifications.first(where: { $0.id == id }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        selectedNotification = note
                        store.markAsRead(note)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .presentationDragIndicator(.visible)
        .sheet(item: $selectedNotification) { note in
            ArgusReportDetailView(notification: note)
        }
        .overlay {
            if showDrawer {
                ArgusDrawerView(isPresented: $showDrawer) { openSheet in
                    drawerSections(openSheet: openSheet)
                }
                .zIndex(200)
            }
        }
    }

    private func drawerSections(openSheet: @escaping (ArgusDrawerView.DrawerSheet) -> Void) -> [ArgusDrawerView.DrawerSection] {
        var sections: [ArgusDrawerView.DrawerSection] = []
        
        sections.append(
            ArgusDrawerView.DrawerSection(
                title: "Ekranlar",
                items: [
                    ArgusDrawerView.DrawerItem(title: "Alkindus Merkez", subtitle: "Yapay zeka merkezi", icon: "AlkindusIcon") {
                        NavigationRouter.shared.navigate(to: .alkindusDashboard)
                        showDrawer = false
                    },
                    ArgusDrawerView.DrawerItem(title: "Piyasalar", subtitle: "Kokpit ekranı", icon: "chart.line.uptrend.xyaxis") {
                        deepLinkManager.navigate(to: .kokpit)
                        showDrawer = false
                    },
                    ArgusDrawerView.DrawerItem(title: "Portföy", subtitle: "Pozisyonlar", icon: "briefcase.fill") {
                        deepLinkManager.navigate(to: .portfolio)
                        showDrawer = false
                    },
                    ArgusDrawerView.DrawerItem(title: "Ayarlar", subtitle: "Tercihler", icon: "gearshape") {
                        deepLinkManager.navigate(to: .settings)
                        showDrawer = false
                    }
                ]
            )
        )
        
        sections.append(
            ArgusDrawerView.DrawerSection(
                title: "Bildirimler",
                items: [
                    ArgusDrawerView.DrawerItem(title: "Tumunu Oku", subtitle: "Tum bildirimleri temizle", icon: "checkmark.circle") {
                        store.markAllRead()
                        showDrawer = false
                    }
                ]
            )
        )
        
        sections.append(ArgusDrawerView.commonToolsSection(openSheet: openSheet))

        return sections
    }
}

struct NotificationRow: View {
    let notification: ArgusNotification

    private var tone: ArgusChipTone {
        switch notification.type {
        case .buyOpportunity:  return .aurora
        case .sellWarning:     return .crimson
        case .tradeExecuted:   return .aurora
        case .positionClosed:  return .neutral
        case .alert:           return .titan
        case .marketUpdate:    return .holo
        case .dailyReport,
             .weeklyReport:    return .motor(.alkindus)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tone.foreground.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: iconName(for: notification.type))
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .semibold))
                    .foregroundColor(tone.foreground)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(notification.headline)
                        .font(InstitutionalTheme.Typography.bodyStrong)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if !notification.isRead {
                        ArgusDot(color: InstitutionalTheme.Colors.crimson, size: 7)
                    }
                }

                Text(notification.summary)
                    .font(InstitutionalTheme.Typography.caption)
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    ArgusChip(categoryLabel(notification.type), tone: tone)
                    Spacer(minLength: 4)
                    Text(notification.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(DesignTokens.Fonts.custom(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(notification.isRead
                    ? DesignTokens.Colors.background
                    : DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                .stroke(notification.isRead
                        ? DesignTokens.Colors.border
                        : tone.foreground.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
    }

    func iconName(for type: ArgusNotification.NotificationType) -> String {
        switch type {
        case .buyOpportunity: return "arrow.up.right.circle.fill"
        case .sellWarning:    return "exclamationmark.triangle.fill"
        case .marketUpdate:   return "chart.bar.doc.horizontal"
        case .tradeExecuted:  return "checkmark.circle.fill"
        case .positionClosed: return "xmark.circle.fill"
        case .alert:          return "bell.fill"
        case .dailyReport:    return "doc.text.fill"
        case .weeklyReport:   return "calendar.badge.checkmark"
        }
    }

    func categoryLabel(_ type: ArgusNotification.NotificationType) -> String {
        switch type {
        case .buyOpportunity: return "AL FIRSATI"
        case .sellWarning:    return "SAT UYARISI"
        case .marketUpdate:   return "PİYASA"
        case .tradeExecuted:  return "İŞLEM"
        case .positionClosed: return "KAPANIŞ"
        case .alert:          return "UYARI"
        case .dailyReport:    return "GÜNLÜK"
        case .weeklyReport:   return "HAFTALIK"
        }
    }
}

struct ArgusReportDetailView: View {
    let notification: ArgusNotification
    @ObservedObject private var market = MarketViewModel.shared
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    CompanyLogoView(symbol: notification.symbol, size: 48)
                    VStack(alignment: .leading) {
                        Text(notification.symbol)
                            .font(InstitutionalTheme.Typography.title)
                            .bold()
                        Text(notification.timestamp.formatted())
                            .font(InstitutionalTheme.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                    Spacer()
                    
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                }
                .padding(.bottom)
                
                Text(LocalizedStringKey(notification.detailedReport))
                    .font(InstitutionalTheme.Typography.body)
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .institutionalCard(scale: .standard, elevated: false)
                
                Spacer(minLength: 40)
                
                if notification.type == .buyOpportunity || notification.type == .sellWarning {
                    Button(action: {
                        executeAction()
                    }) {
                        HStack {
                            Image(systemName: notification.type == .buyOpportunity ? "bolt.fill" : "xmark.circle.fill")
                            Text(notification.type == .buyOpportunity ? "Sinyali Uygula: 1000$ AL" : "Sinyali Uygula: SAT")
                                .font(InstitutionalTheme.Typography.bodyStrong)
                                .bold()
                        }
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(notification.type == .buyOpportunity ? DesignTokens.Colors.success : DesignTokens.Colors.error)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    }
                }
            }
            .padding()
        }
        .background(DesignTokens.Colors.background.ignoresSafeArea())
    }
    
    private func executeAction() {
        if notification.type == .buyOpportunity {
            if let quote = market.quotes[notification.symbol] {
                let price = quote.currentPrice
                if price > 0 {
                    let qty = 1000.0 / price
                    ExecutionStateViewModel.shared.buy(
                        symbol: notification.symbol,
                        quantity: qty,
                        source: .autoPilot,
                        rationale: "Argus Raporu Onayı (\(notification.headline))"
                    )
                }
            }
        } else if notification.type == .sellWarning {
            let openTrades = PortfolioStore.shared.trades.filter { $0.symbol == notification.symbol && $0.isOpen }
            for trade in openTrades {
                let price = market.quotes[trade.symbol]?.currentPrice ?? trade.entryPrice
                PortfolioStore.shared.sell(tradeId: trade.id, currentPrice: price, reason: "Sinyal uyarısı kapatma")
            }
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        presentationMode.wrappedValue.dismiss()
    }
}
