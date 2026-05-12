import SwiftUI
struct TransactionDetailView: View {
    let transaction: Transaction
    let snapshot: DecisionSnapshot?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Transaction Summary
                    VStack(spacing: 8) {
                        Text(transaction.type == .buy ? "ALIŞ İŞLEMİ" : "SATIŞ İŞLEMİ")
                            .font(.headline)
                            .bold()
                            .foregroundColor(transaction.type == .buy ? InstitutionalTheme.Colors.aurora : InstitutionalTheme.Colors.crimson)
                        
                        Text(transaction.symbol)
                            .font(DesignTokens.Fonts.custom(size: 32, weight: .heavy, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        
                        Text(transaction.date.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                    }
                    .padding(.top)
                    
                    Divider().background(DesignTokens.Colors.Overlay.l10)
                    
                    // 2. Decision Rationale (The "Why")
                    // Handle MANUAL logic explicitly
                    if transaction.source == "MANUAL" {
                         VStack(alignment: .leading, spacing: 12) {
                             HStack {
                                 Image(systemName: "person.fill.checkmark")
                                     .foregroundColor(InstitutionalTheme.Colors.holo)
                                 Text("Manuel İşlem (Kullanıcı Kararı)")
                                     .font(.headline)
                                     .bold()
                                     .foregroundColor(DesignTokens.Colors.textPrimary)
                             }
                             
                             Text("Bu işlem kullanıcı tarafından manuel olarak girilmiştir. Sistem sinyallerinden bağımsızdır.")
                                 .font(.body)
                                 .foregroundColor(DesignTokens.Colors.textTertiary)
                                 .padding()
                                 .background(DesignTokens.Colors.surface)
                                 .cornerRadius(8)
                             
                             // Optional: Show what the system THOUGHT at that time
                             if let s = snapshot {
                                  DisclosureGroup("O Sırada Argus Ne Düşünüyordu?") {
                                      AgoraDetailPanel(
                                          symbol: transaction.symbol,
                                          snapshot: s,
                                          trace: nil
                                      )
                                      .padding(.top, 8)
                                  }
                                  .foregroundColor(DesignTokens.Colors.textSecondary)
                             }
                         }
                         .padding(.horizontal)
                    } else if let s = snapshot {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .foregroundColor(InstitutionalTheme.Colors.holo)
                                Text("Karar Mekanizması (Argus/Agora)")
                                    .font(.headline)
                                    .bold()
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                            }
                            
                            AgoraDetailPanel(
                                symbol: transaction.symbol,
                                snapshot: s,
                                trace: nil // If we had trace we could pass it
                            )
                        }
                        .padding(.horizontal)
                    } else {
                        // Fallback
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Karar Notları")
                                .font(.headline)
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                            
                            if let reason = transaction.reasonCode {
                                Text(TransactionDetailView.humanizedReason(reason))
                                    .font(.body)
                                    .foregroundColor(DesignTokens.Colors.textTertiary)
                                    .padding()
                                    .background(DesignTokens.Colors.surface)
                                    .cornerRadius(8)
                            } else {
                                Text("Bu işlem için detaylı karar kaydı bulunamadı.")
                                    .italic()
                                    .foregroundColor(DesignTokens.Colors.textTertiary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // 3. Alkindus Post-Mortem (Satış işlemlerinde)
                    if transaction.type == .sell {
                        AlkindusVerdictSection(symbol: transaction.symbol)
                    }

                    // 4. Execution Detail
                    VStack(alignment: .leading, spacing: 16) {
                        Text("İşlem Detayları")
                            .font(.headline)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        
                        VStack(spacing: 0) {
                            let currencySymbol = transaction.symbol.hasSuffix(".IS") ? "₺" : "$"
                            DetailRow(text: "Fiyat: \(currencySymbol)\(String(format: "%.2f", transaction.price))")
                            Divider().background(DesignTokens.Colors.surface)
                            
                            // Highlighted Amount
                            HStack {
                                Text("Toplam Tutar")
                                    .font(.subheadline)
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                                Spacer()
                                let currencySymbol = transaction.symbol.hasSuffix(".IS") ? "₺" : "$"
                                Text("\(currencySymbol)\(String(format: "%.2f", transaction.amount))")
                                    .font(DesignTokens.Fonts.custom(size: 20, weight: .heavy, design: .monospaced))
                                    .foregroundColor(InstitutionalTheme.Colors.holo)
                            }
                            .padding()
                            
                            Divider().background(DesignTokens.Colors.surface)
                            DetailRow(text: "Kaynak: \(transaction.source ?? "N/A")")
                            if let fee = transaction.fee {
                                Divider().background(DesignTokens.Colors.surface)
                                let currencySymbol = transaction.symbol.hasSuffix(".IS") ? "₺" : "$"
                                DetailRow(text: "Komisyon: \(currencySymbol)\(String(format: "%.2f", fee))")
                            }
                        }
                        .background(DesignTokens.Colors.surface.opacity(0.5))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                }
                .padding(.bottom, 20)
            }
            .background(DesignTokens.Colors.background.ignoresSafeArea())
            .navigationTitle("İşlem Detayı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Helpers
extension TransactionDetailView {
    static func humanizedReason(_ code: String) -> String {
        switch code {
        case "STOP_LOSS":             return "Stop Loss — Belirlenen stop seviyesinde otomatik satış gerçekleşti."
        case "STOP_LOSS_RETROACTIVE": return "Stop Loss (Gecikmeli) — Uygulama kapalıyken fiyat stop seviyesini geçti. Satış, önceden belirlenen stop fiyatından gerçekleştirildi."
        case "TAKE_PROFIT":           return "Kar Al — Belirlenen hedef fiyata ulaşıldı, otomatik satış gerçekleşti."
        case "TAKE_PROFIT_RETROACTIVE": return "Kar Al (Gecikmeli) — Uygulama kapalıyken fiyat hedef seviyesini geçti. Satış, önceden belirlenen hedef fiyatından gerçekleştirildi."
        default:                      return code
        }
    }
}

// Console Style History Row

