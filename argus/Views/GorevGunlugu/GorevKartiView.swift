import SwiftUI

// MARK: - GorevKartiView

/// Tek bir `GorevAnlatisi` kaydını kart olarak gösteren bileşen.
/// Sol aksanlı çubuk → üst satır (sembol, karar tipi, adet, tarih) →
/// anlatı metni → miktar açıklaması → stop/hedef satırı.
struct GorevKartiView: View {
    let anlatim: GorevAnlatisi

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Sol aksan çubuğu
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)

            // MARK: Kart içeriği
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                ustSatir
                anlatimMetni

                if let miktar = anlatim.miktarAciklamasi {
                    miktarMetni(miktar)
                }

                if anlatim.kararTipi == .alim || anlatim.kararTipi == .satim {
                    stopHedefSatiri
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
        .institutionalCard()
    }

    // MARK: - Üst Satır

    private var ustSatir: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(anlatim.symbol)
                .font(DesignTokens.Fonts.custom(size: 16, weight: .bold))
                .foregroundColor(DesignTokens.Colors.textPrimary)

            Text("·")
                .foregroundColor(DesignTokens.Colors.textTertiary)

            Text(anlatim.kararTipi.baslik)
                .font(DesignTokens.Fonts.custom(size: 13, weight: .semibold))
                .foregroundColor(accentColor)

            if anlatim.quantity > 0 {
                Text("·")
                    .foregroundColor(DesignTokens.Colors.textTertiary)

                Text("\(Int(anlatim.quantity)) adet")
                    .font(DesignTokens.Fonts.custom(size: 13, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }

            Spacer()

            tarihGrubu
        }
    }

    // MARK: - Tarih (sağ üst)

    private var tarihGrubu: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(saatFormatla(anlatim.timestamp))
                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.textPrimary)

            Text(tarihFormatla(anlatim.timestamp))
                .font(DesignTokens.Fonts.custom(size: 10, weight: .regular))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
    }

    // MARK: - Anlatım metni

    private var anlatimMetni: some View {
        Text(anlatim.aciklama)
            .font(DesignTokens.Fonts.custom(size: 13, weight: .regular))
            .foregroundColor(DesignTokens.Colors.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Miktar açıklaması

    private func miktarMetni(_ miktar: String) -> some View {
        Text(miktar)
            .font(DesignTokens.Fonts.custom(size: 12, weight: .medium))
            .foregroundColor(DesignTokens.Colors.textTertiary)
    }

    // MARK: - Stop / Hedef satırı

    @ViewBuilder
    private var stopHedefSatiri: some View {
        let hasStop = anlatim.stopLoss != nil
        let hasTarget = anlatim.takeProfit != nil

        if hasStop || hasTarget {
            HStack(spacing: DesignTokens.Spacing.lg) {
                if let stop = anlatim.stopLoss {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Circle()
                            .fill(DesignTokens.Colors.error)
                            .frame(width: 6, height: 6)

                        Text("Stop: \(fiyatFormatla(stop))")
                            .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                    }
                }

                if let target = anlatim.takeProfit {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Circle()
                            .fill(DesignTokens.Colors.success)
                            .frame(width: 6, height: 6)

                        Text("Hedef: \(fiyatFormatla(target))")
                            .font(DesignTokens.Fonts.custom(size: 11, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Accent rengi

    private var accentColor: Color {
        switch anlatim.kararTipi {
        case .alim:       return DesignTokens.Colors.success
        case .satim:      return DesignTokens.Colors.error
        case .pasGecildi: return DesignTokens.Colors.textTertiary
        case .engellendi: return DesignTokens.Colors.warning
        }
    }

    // MARK: - Fiyat formatlama

    private func fiyatFormatla(_ deger: Double) -> String {
        if deger >= 1_000 {
            return formatNoDecimal(deger)
        } else if deger >= 1 {
            return String(format: "%.2f", deger)
        } else {
            return String(format: "%.4f", deger)
        }
    }

    /// >= 1000 durumunda binlik ayraçlı, ondalıksız formatlama.
    private func formatNoDecimal(_ deger: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = "."
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: NSNumber(value: deger)) ?? "\(Int(deger))"
    }

    // MARK: - Tarih formatlama

    private func saatFormatla(_ tarih: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: tarih)
    }

    private func tarihFormatla(_ tarih: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: tarih)
    }
}

// MARK: - Preview

#Preview("Alım Kartı") {
    GorevKartiView(
        anlatim: GorevAnlatisi(
            kararTipi: .alim,
            dominantFaktor: .teknikGuc(skor: 78),
            aciklama: "Teknik göstergeler güçlü bir alım fırsatına işaret ediyor (skor: 78). Diğer analizler de destekliyor.",
            miktarAciklamasi: "4.250 $ tutarında (dengeli — portföyün %3.2'si).",
            symbol: "AAPL",
            quantity: 15,
            price: 198.50,
            stopLoss: 185.20,
            takeProfit: 225.00,
            timestamp: Date()
        )
    )
    .padding()
    .background(DesignTokens.Colors.background)
}

#Preview("Engellendi Kartı") {
    GorevKartiView(
        anlatim: GorevAnlatisi(
            kararTipi: .engellendi,
            dominantFaktor: .zamanlama(sebep: "15 dk kaldı"),
            aciklama: "Analizler olumlu ancak 15 dk kaldı. Koşullar uygun olduğunda yeniden değerlendirilecek.",
            miktarAciklamasi: nil,
            symbol: "THYAO",
            quantity: 0,
            price: nil,
            stopLoss: nil,
            takeProfit: nil,
            timestamp: Date()
        )
    )
    .padding()
    .background(DesignTokens.Colors.background)
}
