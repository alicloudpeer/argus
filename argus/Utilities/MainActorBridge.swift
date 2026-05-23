import Foundation

/// Senkron olarak MainActor üzerinde bir blok çalıştır.
///
/// `MainActor.assumeIsolated` doğrudan kullanıldığında — eğer çağrıldığı
/// thread aslında main değilse — Swift 6 runtime (iOS 26+) çalışma zamanı
/// assertion'ı patlatır (`_dispatch_assert_queue_fail`). Bu helper:
///
/// - Main thread'deyse: `assumeIsolated` ile doğrudan yürütür (fast path).
/// - Background thread'deyse: `DispatchQueue.main.sync` ile main'e atlar,
///   sonuçla döner.
///
/// Bu, "background'dan MainActor verisine eş zamanlı erişim" gibi
/// köprü senaryolar için kullanılır. Yeni kodda doğal yol `await MainActor.run`'dır;
/// helper sadece mevcut senkron API'ları kırmamak için var.
///
/// **Uyarı:** Main'in başka background task'ı `sync` ile beklediği senaryoda
/// deadlock olur. Pratikte: hot startup path ve UI render dışı çağrıları
/// kapsadığımız için risk düşük; yine de uzun süren bloklar `await MainActor.run`
/// kullanmalı.
@inline(__always)
func runOnMainSync<T>(_ block: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { block() }
    }
    return DispatchQueue.main.sync {
        MainActor.assumeIsolated { block() }
    }
}
