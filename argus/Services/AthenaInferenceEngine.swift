import Foundation

/// Athena Inference Engine (AI Core)
/// Responsible for taking raw factor features and producing a prediction
/// using a learned model (or heuristic weights initially).
final class AthenaInferenceEngine {
    static let shared = AthenaInferenceEngine()
    
    // Default weights (can be updated via training)
    private var currentWeights: AthenaModelWeights
    
    private init() {
        // Ağırlıklar önce bundle'daki JSON config'ten yüklenir (izlenebilir + dışarıdan
        // tweak edilebilir); başarısız olursa hardcoded expert baseline fallback.
        if let loaded = Self.loadWeightsFromBundle() {
            self.currentWeights = loaded
        } else {
            self.currentWeights = AthenaModelWeights(
                version: "Athena-V3-Fallback",
                bias: 0.0,
                qualityWeight: 2.0,
                momentumWeight: 2.0,
                sizeWeight: 1.2,
                riskWeight: 1.5,
                interactionWeights: .init(
                    qualityMomentum: 0.8,
                    momentumRisk: -0.9,
                    qualitySq: -0.4, momentumSq: -0.3, riskSq: -0.6
                )
            )
        }
    }

    /// Bundle'daki `AthenaModelWeights.json`'dan ağırlıkları okur.
    /// JSON formatı `AthenaModelWeights` Codable yapısıyla birebir eşleşmelidir.
    /// Dosya yoksa, parse başarısızsa veya ağırlıklar tutarsızsa nil döner.
    private static func loadWeightsFromBundle() -> AthenaModelWeights? {
        guard let url = Bundle.main.url(forResource: "AthenaModelWeights", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        // lastUpdated YYYY-MM-DD ISO formatında tanımlı — Date decoding özelleştir
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        decoder.dateDecodingStrategy = .formatted(fmt)
        guard let parsed = try? decoder.decode(AthenaModelWeights.self, from: data) else {
            return nil
        }
        let all = [parsed.qualityWeight, parsed.momentumWeight,
                   parsed.sizeWeight, parsed.riskWeight]
        guard all.allSatisfy({ $0 >= 0 && $0 <= 10 }) else { return nil }
        return parsed
    }
    
    /// Update weights (e.g. after training/learning)
    func updateWeights(_ newWeights: AthenaModelWeights) {
        self.currentWeights = newWeights
        print("🧠 Athena weights updated to version: \(newWeights.version)")
    }
    
    /// Run inference on a feature vector with optional regime conditioning.
    func predict(features: AthenaFeatureVector, regime: MarketRegime = .neutral) -> AthenaPrediction {
        let q = features.qualityScore / 100.0
        let m = features.momentumScore / 100.0
        let s = features.sizeScore / 100.0
        let r = features.riskScore / 100.0

        // Regime-conditioned linear weights
        let rm = currentWeights.regimeModifiers?[regime.rawValue]
        let wq = currentWeights.qualityWeight * (rm?.qualityMult ?? 1.0)
        let wm = currentWeights.momentumWeight * (rm?.momentumMult ?? 1.0)
        let ws = currentWeights.sizeWeight * (rm?.sizeMult ?? 1.0)
        let wr = currentWeights.riskWeight * (rm?.riskMult ?? 1.0)

        var score = (q * wq) + (m * wm) + (s * ws) + (r * wr) + currentWeights.bias

        // Polynomial interaction terms
        if let ix = currentWeights.interactionWeights {
            score += q * m * ix.qualityMomentum
            score += m * r * ix.momentumRisk
            // Quadratic (captures diminishing returns at extremes)
            score += q * q * ix.qualitySq
            score += m * m * ix.momentumSq
            score += r * r * ix.riskSq
        }

        // Sigmoid activation → (0, 1), then scale to 0-100
        let finalScore = sigmoid(score) * 100.0

        let dominantFactor = determineDominantFactor(features: features, weights: currentWeights, regime: regime)

        return AthenaPrediction(
            inputFeatures: features,
            predictedScore: finalScore,
            confidence: calculateConfidence(features: features, regime: regime),
            modelUsed: currentWeights.version,
            dominantFactor: dominantFactor
        )
    }

    private func sigmoid(_ x: Double) -> Double {
        1.0 / (1.0 + exp(-x))
    }
    
    private func determineDominantFactor(features: AthenaFeatureVector, weights: AthenaModelWeights, regime: MarketRegime = .neutral) -> String {
        let rm = weights.regimeModifiers?[regime.rawValue]
        let contributions = [
            ("Quality", features.qualityScore * weights.qualityWeight * (rm?.qualityMult ?? 1.0)),
            ("Momentum", features.momentumScore * weights.momentumWeight * (rm?.momentumMult ?? 1.0)),
            ("Size", features.sizeScore * weights.sizeWeight * (rm?.sizeMult ?? 1.0)),
            ("Risk", features.riskScore * weights.riskWeight * (rm?.riskMult ?? 1.0))
        ]
        return contributions.max(by: { $0.1 < $1.1 })?.0 ?? "Unknown"
    }
    
    private func calculateConfidence(features: AthenaFeatureVector, regime: MarketRegime = .neutral) -> Double {
        // Güven, faktörlerin hizalanmasıyla (düşük varyans) ve ekstrem skorlardan uzaklıkla artar.
        //
        // Eski sürüm sabit 0.85 dönüyordu — model ne der ne durumda olursa olsun güven
        // asla değişmiyordu, bu da downstream decision engines'in "yüksek güvenle al"
        // sinyallerini nötr/korku durumlarında bile üretmesine neden oluyordu.
        //
        // Yeni formül:
        //   1) Hizalanma (alignment): Faktör skorlarının standart sapması düştükçe güven artar.
        //      Varyans 0 → alignment 1.0; varyans 50+ → alignment 0.0.
        //   2) Ekstremlik (extremity): Ortalamanın 50'den uzaklığı (0..1) güveni azıcık artırır.
        //      Nötr skorlar (~50) belirsiz, uçlar (0 veya 100) net sinyal.
        //
        // Sonuç [0.50, 0.95] aralığında clamp edilir; bu "hiçbir zaman tamamen emin değilim"
        // ilkesini korur (kalibre edilmemiş modelde aşırı güven riskli).

        let scores: [Double] = [
            features.qualityScore,
            features.momentumScore,
            features.sizeScore,
            features.riskScore
        ]

        guard !scores.isEmpty else { return 0.70 }

        let mean = scores.reduce(0, +) / Double(scores.count)
        let variance = scores.map { pow($0 - mean, 2) }.reduce(0, +) / Double(scores.count)
        let std = sqrt(variance)

        // Alignment: std 0 → 1.0, std 25 → 0.0 (lineer ceza)
        let alignment = max(0.0, 1.0 - (std / 25.0))

        // Extremity: |mean - 50| / 50 ∈ [0, 1]
        let extremity = min(1.0, abs(mean - 50.0) / 50.0)

        let combined = 0.70 * alignment + 0.30 * extremity

        // Regime penalty: volatile regimes reduce confidence
        let regimePenalty: Double
        switch regime {
        case .newsShock: regimePenalty = 0.15
        case .riskOff: regimePenalty = 0.10
        case .chop: regimePenalty = 0.05
        case .trend, .neutral: regimePenalty = 0.0
        }

        return min(0.95, max(0.45, 0.50 + combined * 0.45 - regimePenalty))
    }
}
