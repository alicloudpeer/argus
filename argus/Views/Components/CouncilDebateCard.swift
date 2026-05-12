import SwiftUI

// MARK: - Council Debate Card
/// Displays the internal council voting process and reasoning for educational purposes
struct CouncilDebateCard: View {
    let title: String
    let icon: String
    let accentColor: Color
    
    let winningProposal: (name: String, action: String, reasoning: String)?
    let votes: [(name: String, decision: VoteDecision, reasoning: String?, weight: Double)]
    let finalDecision: String
    let netSupport: Double
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .foregroundColor(accentColor)
                Text(title)
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                
                Spacer()
                
                // Net support badge
                Text("\(netSupport > 0 ? "+" : "")\(Int(netSupport * 100))%")
                    .font(DesignTokens.Fonts.custom(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(netSupport > 0 ? .green : (netSupport < 0 ? .red : .yellow))
                
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
            }
            
            // Proposal summary (always visible)
            if let proposal = winningProposal {
                HStack(spacing: 8) {
                Image(systemName: "megaphone.fill")
                    .font(DesignTokens.Fonts.custom(size: 12))
                    .foregroundColor(accentColor)
                    
                    Text(proposal.name)
                        .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                        .foregroundColor(accentColor)
                    
                    Text("→")
                        .font(.caption2)
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    
                    Text(proposal.action)
                        .font(DesignTokens.Fonts.custom(size: 11, weight: .bold))
                        .foregroundColor(actionColor(for: proposal.action))
                }
                
                Text(proposal.reasoning)
                    .font(DesignTokens.Fonts.custom(size: 10))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .italic()
                    .lineLimit(2)
            }
            
            // Expanded: Show all votes
            if isExpanded {
                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)

                // 2026-05-05 H-67: caps "OYLAR" tracking 1 → sentence "Oylar".
                VStack(alignment: .leading, spacing: 8) {
                    Text("Oylar")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                    
                    ForEach(Array(votes.enumerated()), id: \.offset) { _, vote in
                        DebateVoteRow(
                            name: vote.name,
                            decision: vote.decision,
                            reasoning: vote.reasoning,
                            weight: vote.weight
                        )
                    }
                }
                
                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)

                // Summary
                HStack {
                    let approveCount = votes.filter { $0.decision == .approve }.count
                    let vetoCount = votes.filter { $0.decision == .veto }.count

                    Text("\(approveCount) onay, \(vetoCount) veto")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)

                    Spacer()

                    Text("→ \(finalDecision)")
                        .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                        .foregroundColor(actionColor(for: finalDecision))
                }
            }
        }
        .padding(12)
        .background(DesignTokens.Colors.surface)
        .cornerRadius(12)
        .overlay(
            // 2026-05-05 H-67: motor accent tinted border (opacity 0.3)
            // → hairline borderSubtle (sade).
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
    }
    
    private func actionColor(for action: String) -> Color {
        let lowercased = action.lowercased()
        if lowercased.contains("al") || lowercased.contains("buy") { return .green }
        if lowercased.contains("sat") || lowercased.contains("sell") { return .red }
        return .yellow
    }
}

// MARK: - Debate Vote Row
struct DebateVoteRow: View {
    let name: String
    let decision: VoteDecision
    let reasoning: String?
    let weight: Double
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(decision.emoji)
                .font(DesignTokens.Fonts.custom(size: 12))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    Text(decision.rawValue)
                        .font(DesignTokens.Fonts.custom(size: 10, weight: .bold))
                        .foregroundColor(decisionColor)
                    
                    if weight > 0.8 {
                        Text("⚡")
                            .font(DesignTokens.Fonts.custom(size: 8))
                    }
                }
                
                if let reason = reasoning, !reason.isEmpty {
                    Text(reason)
                        .font(DesignTokens.Fonts.custom(size: 9))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
    }
    
    private var decisionColor: Color {
        switch decision {
        case .approve: return .green
        case .veto: return .red
        case .abstain: return .gray
        }
    }
}

// MARK: - Atlas Debate Card Helper
struct AtlasDebateCard: View {
    let decision: AtlasDecision
    
    var body: some View {
        let proposal: (name: String, action: String, reasoning: String)? = {
            guard let p = decision.winningProposal else { return nil }
            return (p.proposerName, p.action.rawValue, p.reasoning)
        }()
        
        let votes: [(name: String, decision: VoteDecision, reasoning: String?, weight: Double)] = decision.votes.map {
            ($0.voterName, $0.decision, $0.reasoning, $0.weight)
        }
        
        // 2026-05-05 H-67: "Atlas Konseyi" mitoloji adı → "Bilanço konseyi"
        // sade. Mavi accent → textSecondary (renk artık border'da yok).
        CouncilDebateCard(
            title: "Bilanço konseyi",
            icon: "building.columns",
            accentColor: DesignTokens.Colors.textSecondary,
            winningProposal: proposal,
            votes: votes,
            finalDecision: decision.action.rawValue,
            netSupport: decision.netSupport
        )
    }
}

// MARK: - Grand Council Debate Card
//
// ArgusGrandDecision için karar patikası kartı: kim oy verdi, hangi yönde,
// hangi modül veto etti, kim oy vermedi neden, danışmanlar ne dedi.
//
// 2026-04-25 — Dürüstlük revizyonu:
// 1. SAT oyu artık "VETO" diye gösterilmiyor. Önceki version
//    `.sell → .veto` mapping yapıyordu, ama satış OYU ile sert VETO ayrı şeyler.
//    Sert veto sadece ModuleVeto listesindeki kayıtlar.
// 2. "BEKLEYEN MODÜL" bölümü: Atlas/Hermes oy vermediyse (snapshot yok / haber
//    yok), bunlar ayrı bölümde "veri bekleniyor" notuyla gösterilir.
//    Eskiden contributors listesi sadece oy verenleri içeriyordu — kullanıcı
//    "2 modül oy verdi" görüp "kalan modüller nerede?" diye haklı şikayet ediyordu.
struct GrandCouncilDebateCard: View {
    let decision: ArgusGrandDecision
    @State private var isExpanded: Bool = true

    /// Tüm Council üyeleri — oy verenler + bekleyenler.
    /// Bekleyenler: Atlas (atlasDecision nil), Hermes (hermesDecision nil).
    private var pendingMembers: [(name: String, reason: String)] {
        var pending: [(String, String)] = []
        let voted = Set(decision.contributors.map { $0.module.lowercased() })
        if decision.atlasDecision == nil && !voted.contains("atlas") {
            pending.append(("Atlas", "Bilanço/temel veri yüklenmedi"))
        }
        if decision.hermesDecision == nil && !voted.contains("hermes") {
            pending.append(("Hermes", "Haber verisi yok"))
        }
        return pending
    }

    private var totalExpectedVoters: Int {
        decision.contributors.count + pendingMembers.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 2026-05-05 H-67: caps mono "KARAR PATİKASI" tracking 1.4 →
            // sentence "Karar patikası". Holo motor logo kalktı.
            HStack {
                Text("Karar patikası")
                    .font(DesignTokens.Fonts.custom(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
                Text(decision.action.rawValue)
                    .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
                    .foregroundColor(actionColor(decision.action))
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
            }

            // Reasoning özet (sayım + ağırlık + eşik dahil)
            Text(decision.reasoning)
                .font(DesignTokens.Fonts.custom(size: 11))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if isExpanded {
                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 0.5)

                // 2026-05-05 H-67: caps başlıklar tracking 1 → sentence.
                // Oy verenler
                VStack(alignment: .leading, spacing: 8) {
                    Text("Oylar · \(decision.contributors.count) / \(totalExpectedVoters) modül")
                        .font(DesignTokens.Fonts.custom(size: 12))
                        .foregroundColor(DesignTokens.Colors.textTertiary)
                    ForEach(Array(decision.contributors.enumerated()), id: \.offset) { _, contrib in
                        contributorRow(contrib)
                    }
                }

                // Oy vermeyenler (Atlas/Hermes vb. veri yok durumu)
                if !pendingMembers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bekleyen · \(pendingMembers.count) modül")
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(InstitutionalTheme.Colors.titan)
                        ForEach(Array(pendingMembers.enumerated()), id: \.offset) { _, p in
                            pendingRow(name: p.name, reason: p.reason)
                        }
                    }
                }

                // Hard veto'lar (gerçek veto — ModuleVeto listesi)
                if !decision.vetoes.isEmpty {
                    Rectangle()
                        .fill(DesignTokens.Colors.borderSubtle)
                        .frame(height: 0.5)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Veto · \(decision.vetoes.count)")
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(InstitutionalTheme.Colors.crimson)
                        ForEach(Array(decision.vetoes.enumerated()), id: \.offset) { _, veto in
                            HStack(spacing: 6) {
                                Image(systemName: "hand.raised.fill")
                                    .font(DesignTokens.Fonts.custom(size: 9))
                                    .foregroundColor(InstitutionalTheme.Colors.crimson)
                                Text(veto.module)
                                    .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text("·").foregroundColor(DesignTokens.Colors.textTertiary)
                                Text(veto.reason)
                                    .font(DesignTokens.Fonts.custom(size: 10))
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                // Danışman notları
                if !decision.advisors.isEmpty {
                    Rectangle()
                        .fill(DesignTokens.Colors.borderSubtle)
                        .frame(height: 0.5)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Danışman notları · \(decision.advisors.count)")
                            .font(DesignTokens.Fonts.custom(size: 12))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                        ForEach(Array(decision.advisors.enumerated()), id: \.offset) { _, note in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: noteIcon(for: note.tone))
                                    .font(DesignTokens.Fonts.custom(size: 9))
                                    .foregroundColor(noteColor(for: note.tone))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.module)
                                        .font(DesignTokens.Fonts.custom(size: 10, weight: .bold))
                                        .foregroundColor(DesignTokens.Colors.textPrimary)
                                    Text(note.advice)
                                        .font(DesignTokens.Fonts.custom(size: 10))
                                        .foregroundColor(DesignTokens.Colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(DesignTokens.Colors.surface)
        .cornerRadius(12)
        .overlay(
            // 2026-05-05 H-67: holo motor tinted border (opacity 0.3) →
            // hairline borderSubtle.
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    /// Modül oy satırı — AL/SAT/BEKLE yönünde + güven yüzdesi + 1 satır rationale.
    @ViewBuilder
    private func contributorRow(_ contrib: ModuleContribution) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: voteIcon(for: contrib.action))
                .font(DesignTokens.Fonts.custom(size: 11, weight: .bold))
                .foregroundColor(voteColor(for: contrib.action))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(contrib.module)
                        .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Text(voteLabel(for: contrib.action))
                        .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                        .foregroundColor(voteColor(for: contrib.action))
                    Spacer()
                    Text("%\(Int(abs(contrib.confidence) * 100))")
                        .font(DesignTokens.Fonts.custom(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                if !contrib.reasoning.isEmpty {
                    Text(contrib.reasoning)
                        .font(DesignTokens.Fonts.custom(size: 10))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// Bekleyen (oy vermemiş) modül satırı — neden oy vermediğini açıklar.
    @ViewBuilder
    private func pendingRow(name: String, reason: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock")
                .font(DesignTokens.Fonts.custom(size: 10))
                .foregroundColor(InstitutionalTheme.Colors.titan)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Text("Bekleniyor")
                        .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.titan)
                    Spacer()
                }
                Text(reason)
                    .font(DesignTokens.Fonts.custom(size: 10))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func voteIcon(for action: ProposedAction) -> String {
        switch action {
        case .buy:  return "arrow.up.circle.fill"
        case .sell: return "arrow.down.circle.fill"
        case .hold: return "minus.circle.fill"
        }
    }

    private func voteLabel(for action: ProposedAction) -> String {
        switch action {
        case .buy:  return "Al"
        case .sell: return "Sat"
        case .hold: return "Bekle"
        }
    }

    private func voteColor(for action: ProposedAction) -> Color {
        switch action {
        case .buy:  return InstitutionalTheme.Colors.aurora
        case .sell: return InstitutionalTheme.Colors.crimson
        case .hold: return DesignTokens.Colors.textSecondary
        }
    }

    private func actionColor(_ action: ArgusAction) -> Color {
        switch action {
        case .aggressiveBuy, .accumulate: return InstitutionalTheme.Colors.aurora
        case .trim, .liquidate: return InstitutionalTheme.Colors.crimson
        case .neutral: return DesignTokens.Colors.textSecondary
        }
    }

    private func noteIcon(for tone: AdvisorNote.AdvisorTone) -> String {
        switch tone {
        case .positive: return "checkmark.seal.fill"
        case .caution:  return "exclamationmark.triangle.fill"
        case .warning:  return "xmark.octagon.fill"
        case .neutral:  return "info.circle"
        }
    }

    private func noteColor(for tone: AdvisorNote.AdvisorTone) -> Color {
        switch tone {
        case .positive: return InstitutionalTheme.Colors.aurora
        case .caution:  return InstitutionalTheme.Colors.titan
        case .warning:  return InstitutionalTheme.Colors.crimson
        case .neutral:  return DesignTokens.Colors.textSecondary
        }
    }
}

// MARK: - Orion Debate Card Helper
struct OrionDebateCard: View {
    let decision: CouncilDecision
    
    var body: some View {
        let proposal: (name: String, action: String, reasoning: String)? = {
            guard let p = decision.winningProposal else { return nil }
            return (p.proposerName, p.action.rawValue, p.reasoning)
        }()
        
        let votes: [(name: String, decision: VoteDecision, reasoning: String?, weight: Double)] = decision.votes.map {
            ($0.voterName, $0.decision, $0.reasoning, $0.weight)
        }
        
        // 2026-05-05 H-67: "Orion Konseyi" mitoloji adı → "Teknik konseyi".
        // Mor accent → textSecondary.
        CouncilDebateCard(
            title: "Teknik konseyi",
            icon: "waveform.path.ecg",
            accentColor: DesignTokens.Colors.textSecondary,
            winningProposal: proposal,
            votes: votes,
            finalDecision: decision.action.rawValue,
            netSupport: decision.netSupport
        )
    }
}
