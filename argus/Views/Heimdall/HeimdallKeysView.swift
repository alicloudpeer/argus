import SwiftUI

/// V5 API Key merkezi — `APIKeyCenterView`'a routing alias.
///
/// 2026-05-11: Eski sarıcı kaldırıldı. APIKeyCenterView artık kendi
/// başlığını (geri butonu dahil) çizdiği için ArgusNavHeader sarması
/// çift başlık + ÇIKIŞSIZ EKRAN'a yol açıyordu (leadingDeco `.bars3`
/// idi, geri butonu yoktu, navigationBarHidden(true) sistem back'i de
/// gizliyordu). Şimdi sadece APIKeyCenterView gösterilir.
struct HeimdallKeysView: View {
    var body: some View {
        APIKeyCenterView()
    }
}
