import SwiftUI
import UIKit
@preconcurrency import UserNotifications

extension Notification.Name {
    static let stacksDidRegisterForRemoteNotifications = Notification.Name("stacks.didRegisterForRemoteNotifications")
    static let stacksDidOpenPriceAlert = Notification.Name("stacks.didOpenPriceAlert")
}

private final class StacksAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let cachedPushTokenKey = "stacks.notifications.deviceToken"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.cachedPushTokenKey)
        NotificationCenter.default.post(name: .stacksDidRegisterForRemoteNotifications, object: token)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard info["type"] as? String == "price_alert",
              let stackValue = info["stackID"] as? String,
              let itemValue = info["itemID"] as? String,
              let stackID = UUID(uuidString: stackValue),
              let itemID = UUID(uuidString: itemValue) else { return }
        await MainActor.run {
            NotificationCenter.default.post(
                name: .stacksDidOpenPriceAlert,
                object: nil,
                userInfo: ["stackID": stackID, "itemID": itemID]
            )
        }
    }
}

@main
struct StacksApp: App {
    @UIApplicationDelegateAdaptor(StacksAppDelegate.self) private var appDelegate
    @State private var session = AppSession(services: .configured())
    @State private var pro = StacksPro()
    @State private var priceAlerts = PriceAlertCenter()

    init() {
        StacksFontRegistration.registerBundledFonts()
        pro.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(pro)
                .environment(priceAlerts)
                .environment(\.appServices, session.services)
                #if DEBUG
                .task {
                    if ProcessInfo.processInfo.environment["STACKS_CURATED_BATCH"] == "1" {
                        await CuratedBatchImport.run()
                    } else if ProcessInfo.processInfo.environment["STACKS_CURATED_AUDIT"] == "1" {
                        await CuratedBatchImport.auditCandidates()
                    } else if ProcessInfo.processInfo.environment["STACKS_CURATED_REFINE"] != nil {
                        await CuratedBatchImport.refineImages()
                    }
                }
                #endif
                .task(id: session.currentAccountID) {
                    guard let accountID = session.currentAccountID else {
                        Analytics.reset()
                        await pro.setAccount(nil)
                        await priceAlerts.setAccount(nil)
                        return
                    }
                    // RevenueCat starts after authentication so its app user ID
                    // is the same Supabase UUID used by server-side Pro limits.
                    Analytics.identify(accountID)
                    await pro.setAccount(accountID)
                    await pro.start()
                    await priceAlerts.setAccount(accountID)
                    if let token = UserDefaults.standard.string(forKey: StacksAppDelegate.cachedPushTokenKey) {
                        try? await SupabasePushTokenService().register(deviceToken: token)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .stacksDidRegisterForRemoteNotifications)) { note in
                    guard session.currentAccountID != nil, let token = note.object as? String else { return }
                    Task { try? await SupabasePushTokenService().register(deviceToken: token) }
                }
                .onOpenURL { url in
                    Task { await session.handleIncomingURL(url) }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    Task { await session.handleIncomingURL(url) }
                }
        }
    }
}

#if DEBUG
/// Runs the same on-device product import and Apple Vision cutout path as the
/// paste-link sheet, without entering a long editorial list through the UI.
/// The output lives in this simulator app's Documents/CuratedBatch directory.
private enum CuratedBatchImport {
    private static let stackID = UUID(uuidString: "49949342-C9A7-400E-B43F-A992A8522951")!
    private static let links = [
        "https://store.billieeilish.com/products/eilish-eau-de-parfum",
        "https://www.thehydrojug.com/product/cream-40oz-traveler",
        "https://us.kayali.com/products/lovefest-burning-cherry-48",
        "https://www.nordstrom.com/s/ugg-cozy-knit-genuine-shearling-slipper-women/5025430",
        "https://www.stadiumgoods.com/products/samba-wales-bonner-leopard-pony-hair-123333",
        "https://saiehello.com/products/the-vanity-case-1",
        "https://scuffers.com/products/globally-navy-hoodie",
        "https://us.jellycat.com/amuseables-croissant/",
        "https://us.refybeauty.com/products/duo-brush",
        "https://www.rhodeskin.com/collections/peptide-lip-tint",
        "https://www.birkenstock.com/us/boston-soft-footbed-suede-leather/boston-suede-suedeleather-softfootbed-eva-u_46.html",
        "https://saiehello.com/products/glowy-super-gel-luminizer",
        "https://www.glossier.com/products/the-beauty-bag",
        "https://www.rhodeskin.com/products/glazing-milk",
        "https://www.rhodeskin.com/collections/pocket-blush",
        "https://www.aloyoga.com/products/a0286w-90s-claw-clip-brown-tortoise",
        "https://www.umbra.com/products/dachsie-ring-holder",
        "https://www.aloyoga.com/products/a0357u-unisex-throwback-sock-white-black",
        "https://www.glossier.com/products/glossier-you-doux",
    ]

    private struct Result: Encodable, Sendable {
        let index: Int
        let id: String
        let sourceURL: String
        let title: String
        let brand: String
        let price: Decimal?
        let currencyCode: String
        let originalImage: String?
        let cutoutImage: String?
        let warning: String?
    }

    private struct Candidate: Encodable {
        let index: Int
        let url: String
        let filename: String?
    }

    static func refineImages() async {
        do {
            let root = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("CuratedBatch", isDirectory: true)
            let audit = root.appendingPathComponent("candidate-audit", isDirectory: true)
            let output = root.appendingPathComponent("refined", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let candidates: [(Int, String?, String?)] = [
                (1, nil, "https://reblscents.com/cdn/shop/files/BillieEilish-Eilish.png?v=1695928017&width=1200"),
                (2, "02-03.image", nil),
                (4, nil, "https://n.nordstrommedia.com/it/d2549b1d-5a75-47f1-ae8b-936226d53527.jpeg?crop=pad&h=1170&trim=color&w=780"),
                (7, nil, "https://cdn.shopify.com/s/files/1/0035/9828/6912/files/hoddie_back.jpg?v=1772802636"),
                (11, nil, "https://www.birkenstock.com/dw/image/v2/BLZD_PRD/on/demandware.static/-/Sites-master-catalog-amer/default/dw5b1a36d6/560773/560773.jpg?sw=1200&sh=1200&sm=fit&q=85"),
                (13, "13-05.image", nil),
                (15, nil, "https://cdn.shopify.com/s/files/1/0606/5451/8510/files/tanline-main_e79dd56e-2264-4542-8247-40e659c3825b.png?v=1765924635"),
                (17, "17-07.image", nil),
                (18, "18-02.image", nil),
            ]
            for (number, filename, rawURL) in candidates {
                if ProcessInfo.processInfo.environment["STACKS_CURATED_REFINE"] == "2" && ![1, 2, 7, 15].contains(number) {
                    continue
                }
                if ProcessInfo.processInfo.environment["STACKS_CURATED_REFINE"] == "3" && number != 18 {
                    continue
                }
                let prefix = String(format: "%02d", number)
                let data: Data
                if let filename {
                    data = try Data(contentsOf: audit.appendingPathComponent(filename))
                } else if let rawURL, let url = URL(string: rawURL) {
                    let (downloaded, _) = try await URLSession.shared.data(from: url)
                    data = downloaded
                } else { continue }
                let original = output.appendingPathComponent("\(prefix)-original.image")
                try data.write(to: original, options: .atomic)
                let item = StackItem(
                    id: UUID(), stackID: stackID, title: "Curated product", brand: "",
                    shortDescription: "", price: 0, currencyCode: "USD",
                    sourceURL: URL(string: links[number - 1])!, buyURL: URL(string: links[number - 1])!, affiliateURL: nil,
                    originalImageURL: original, removedBackgroundImageURL: nil,
                    removalStatus: .processing,
                    placement: StickerPlacement(xRatio: 0.5, yRatio: 0.5, scale: 1, rotationDegrees: 0),
                    addSource: .pastedLink, claimStatus: nil
                )
                if let removed = try await AppleVisionBackgroundRemovalService().removeBackground(for: item) {
                    let destination = output.appendingPathComponent("\(prefix)-cutout.png")
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: removed, to: destination)
                    print("Refined cutout \(prefix)")
                }
            }
            try "complete".write(to: output.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
        } catch {
            print("Curated refinement failed: \(error.localizedDescription)")
        }
    }

    static func auditCandidates() async {
        do {
            let directory = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("CuratedBatch/candidate-audit", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for productIndex in [0, 1, 3, 6, 10, 12, 14, 16, 17] {
                let source = URL(string: links[productIndex])!
                let preview = try? await EdgeFunctionProductSearchService().previewProductLink(source)
                var candidates = await ProductPageImageExtractor.productImageURLs(for: source)
                if let image = preview?.imageURL { candidates.append(image) }
                var seen = Set<URL>()
                candidates = candidates.filter { seen.insert($0).inserted }
                var records: [Candidate] = []
                for (index, url) in candidates.prefix(12).enumerated() {
                    let image = await ProductPageImageExtractor.firstDownloadableImage(from: [url])
                    let filename = image.map { _ in String(format: "%02d-%02d.image", productIndex + 1, index + 1) }
                    if let image, let filename {
                        try image.data.write(to: directory.appendingPathComponent(filename), options: .atomic)
                    }
                    records.append(Candidate(index: index, url: url.absoluteString, filename: filename))
                }
                let output = directory.appendingPathComponent(String(format: "%02d.json", productIndex + 1))
                try JSONEncoder().encode(records).write(to: output, options: .atomic)
                print("Curated candidates: \(productIndex + 1), \(records.filter { $0.filename != nil }.count) usable")
            }
            try "complete".write(to: directory.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
        } catch {
            print("Curated candidate audit failed: \(error.localizedDescription)")
        }
    }

    static func run() async {
        do {
            let directory = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("CuratedBatch/fall-reset", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var results: [Result] = []
            for start in stride(from: 0, to: links.count, by: 3) {
                let end = min(start + 3, links.count)
                let batch = await withTaskGroup(of: Result.self, returning: [Result].self) { group in
                    for index in start..<end {
                        group.addTask { await importLink(links[index], index: index, into: directory) }
                    }
                    var finished: [Result] = []
                    for await result in group { finished.append(result) }
                    return finished
                }
                results.append(contentsOf: batch)
                results.sort { $0.index < $1.index }
                let manifest = try JSONEncoder().encode(results)
                try manifest.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
                print("Curated batch imported \(results.count)/\(links.count)")
            }
            try "complete".write(to: directory.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
            print("Curated batch complete: \(directory.path)")
        } catch {
            print("Curated batch failed: \(error.localizedDescription)")
        }
    }

    private static func importLink(_ rawLink: String, index: Int, into directory: URL) async -> Result {
        let source = URL(string: rawLink)!
        let id = UUID()
        var title = ProductPageImageExtractor.fallbackTitle(for: source)
        var brand = ""
        var price: Decimal?
        var currencyCode = "USD"
        var originalImage: String?
        var cutoutImage: String?
        var warning: String?

        do {
            let preview = try await EdgeFunctionProductSearchService().previewProductLink(source)
            title = ProductImportedCopy.conciseTitle(preview.title, brand: preview.brand)
            brand = preview.brand
            price = preview.price
            currencyCode = preview.currencyCode
            warning = preview.importWarning

            var candidates = await ProductPageImageExtractor.productImageURLs(for: preview.sourceURL)
            if let image = preview.imageURL { candidates.append(image) }
            var seen = Set<URL>()
            candidates = candidates.filter { seen.insert($0).inserted }
            var resolved = await ProductPageImageExtractor.firstDownloadableImage(from: candidates)
            if resolved == nil,
               let image = await ProductPageImageExtractor.linkPresentationImageURL(for: preview.sourceURL) {
                resolved = await ProductPageImageExtractor.firstDownloadableImage(from: [image])
            }

            if let resolved {
                let prefix = String(format: "%02d", index + 1)
                let localOriginal = directory.appendingPathComponent("\(prefix)-original.image")
                try resolved.data.write(to: localOriginal, options: .atomic)
                originalImage = localOriginal.lastPathComponent
                let item = StackItem(
                    id: id, stackID: stackID, title: title, brand: brand,
                    shortDescription: "", price: price ?? 0, currencyCode: currencyCode,
                    sourceURL: source, buyURL: source, affiliateURL: nil,
                    originalImageURL: localOriginal, removedBackgroundImageURL: nil,
                    removalStatus: .processing,
                    placement: StickerPlacement(xRatio: 0.5, yRatio: 0.5, scale: 1, rotationDegrees: 0),
                    addSource: .pastedLink, claimStatus: nil
                )
                if let removed = try await AppleVisionBackgroundRemovalService().removeBackground(for: item) {
                    let destination = directory.appendingPathComponent("\(prefix)-cutout.png")
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: removed, to: destination)
                    cutoutImage = destination.lastPathComponent
                }
            } else {
                warning = "No verified downloadable product image; \(warning ?? "retailer image unavailable")"
            }
        } catch {
            warning = error.localizedDescription
        }
        return Result(
            index: index, id: id.uuidString, sourceURL: rawLink, title: title,
            brand: brand, price: price, currencyCode: currencyCode,
            originalImage: originalImage, cutoutImage: cutoutImage, warning: warning
        )
    }
}
#endif
