import Observation
import RevenueCat
import SwiftUI
import UserNotifications
import UIKit

enum ProGate: String, Identifiable {
    case onboarding, settings, itemLimit, collaboratorLimit, priceAlertLimit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onboarding, .settings: "Make the most of\nyour Stacks"
        case .itemLimit: "Keep stacking"
        case .collaboratorLimit: "Bring everyone in"
        case .priceAlertLimit: "Never miss a\nprice drop"
        }
    }

    var message: String {
        switch self {
        case .onboarding: "Start with more room and premium ways to share."
        case .settings: "Make more room for everything you love."
        case .itemLimit: "You've reached 15 items in this Stack."
        case .collaboratorLimit: "You've reached 3 invited people in this Collab."
        case .priceAlertLimit: "Keep an eye on every price with up to 25 active alerts."
        }
    }
}

@MainActor
@Observable
final class StacksPro {
    // These identifiers must match the RevenueCat project. The StoreKit
    // product IDs below are for the App Store, not its separate Test Store.
    static let entitlementID = "stacks_pro"
    static let offeringID = "Stacks Pro"
    static let monthlyID = "stacks.pro.monthly"
    static let annualID = "stacks.pro.annual"
    static let freeItemLimit = 15
    static let freeCollaboratorLimit = 3
    static let freePriceAlertLimit = 1
    static let proPriceAlertLimit = 25

    private(set) var packages: [Package] = []
    private(set) var currentOffering: Offering?
    private(set) var isPro = false
    private(set) var isBusy = false
    private(set) var isConfigured = false
    private(set) var isAccountLinked = false
    var errorMessage: String?
    var gate: ProGate?
    private var resumeAction: (() -> Void)?
    private var accountID: UUID?
    private var cachedExpiry: Date? {
        guard let accountID else { return nil }
        return UserDefaults.standard.object(forKey: "stacks.pro.expiry.\(accountID.uuidString)") as? Date
    }
    private var customerInfoTask: Task<Void, Never>?
    private var usesTestStore = false

    enum BillingPeriod {
        case annual
        case monthly

        var packageType: PackageType { self == .annual ? .annual : .monthly }
    }

    func configure() {
        guard !isConfigured else { return }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "STACKS_REVENUECAT_API_KEY") as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Stacks Pro is not configured for this build. Continue free for now."
            return
        }
        #if !DEBUG
        // A Test Store key crashes RevenueCat's SDK in an App Store build.
        // Fail closed for missing or non-Apple keys as well.
        guard key.hasPrefix("appl_") else {
            errorMessage = "Stacks Pro is not configured for this App Store build."
            return
        }
        #endif
        usesTestStore = key.hasPrefix("test_")
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: key)
        isConfigured = true
    }

    func start() async {
        configure()
        guard isConfigured else { return }
        if let accountID, !isAccountLinked { await setAccount(accountID) }
        if customerInfoTask == nil {
            customerInfoTask = Task { [weak self] in
                guard let self else { return }
                for await customerInfo in Purchases.shared.customerInfoStream {
                    await self.apply(customerInfo)
                }
            }
        }
        do {
            let offerings = try await Purchases.shared.offerings()
            // The dashboard's generic `default` offering includes a lifetime
            // test product. Only the named Stacks Pro offering is appropriate.
            currentOffering = offerings.all[Self.offeringID]
            packages = currentOffering?.availablePackages
                .filter { package in
                    guard package.packageType == .annual || package.packageType == .monthly else { return false }
                    #if DEBUG
                    return true // RevenueCat Test Store uses `yearly` and `monthly`.
                    #else
                    return [Self.monthlyID, Self.annualID].contains(package.storeProduct.productIdentifier)
                    #endif
                }
                .sorted { $0.packageType == .annual && $1.packageType != .annual } ?? []
            if currentOffering == nil || packages.isEmpty {
                errorMessage = "Stacks Pro plans are not available yet. Continue free for now."
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = "Plans are unavailable right now. Please try again later."
        }
        await refreshEntitlement()
    }

    func setAccount(_ id: UUID?) async {
        guard accountID != id || (id != nil && !isAccountLinked) else { return }
        if accountID != id { close() }
        isPro = false
        isAccountLinked = false
        currentOffering = nil
        packages = []
        accountID = id
        guard isConfigured else { return }
        do {
            if let id {
                let result = try await Purchases.shared.logIn(id.uuidString.lowercased())
                guard accountID == id else { return }
                isAccountLinked = true
                await apply(result.customerInfo)
            } else if !Purchases.shared.isAnonymous {
                _ = try await Purchases.shared.logOut()
            }
        } catch {
            errorMessage = "Your Stacks Pro account couldn't be refreshed right now."
        }
    }

    func refreshEntitlement() async {
        guard accountID != nil, isConfigured, isAccountLinked else { isPro = false; return }
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            await apply(customerInfo)
            errorMessage = nil
        } catch {
            // A previously server-verified plan remains usable offline only
            // until its recorded expiration; backend writes still check DB.
            isPro = (cachedExpiry ?? .distantPast) > .now
            errorMessage = isPro ? nil : "Your subscription couldn't be verified right now. Please try again."
            return
        }
        if !usesTestStore, SupabaseConfiguration.fromAppBundle() != nil {
            do {
                _ = try await SupabaseProEntitlementService().sync()
            } catch {
                // A backend outage must not erase an App Store entitlement.
                // Server-side limits remain authoritative and can be retried.
                errorMessage = "Stacks Pro is active, but syncing it to your Stacks account is delayed. Please try again later."
            }
        }
    }

    private func apply(_ customerInfo: CustomerInfo) async {
        let entitlement = customerInfo.entitlements.all[Self.entitlementID]
        let productID = entitlement?.productIdentifier ?? ""
        #if DEBUG
        let allowedProducts = [Self.monthlyID, Self.annualID, "monthly", "yearly"]
        #else
        let allowedProducts = [Self.monthlyID, Self.annualID]
        #endif
        isPro = isAccountLinked && entitlement?.isActive == true && allowedProducts.contains(productID)
        if let accountID {
            UserDefaults.standard.set(isPro ? entitlement?.expirationDate : nil,
                                      forKey: "stacks.pro.expiry.\(accountID.uuidString)")
        }
        if isPro, let action = resumeAction {
            resumeAction = nil
            gate = nil
            action()
        }
    }

    func present(_ reason: ProGate, resume: (() -> Void)? = nil) {
        guard !isPro else { resume?(); return }
        resumeAction = resume
        gate = reason
    }

    @discardableResult
    func requireItemSlot(in stack: Stack, resume: @escaping () -> Void) -> Bool {
        guard !isPro && stack.items.count >= Self.freeItemLimit else { return true }
        present(.itemLimit, resume: resume)
        return false
    }

    @discardableResult
    func requireCollaboratorSlot(in stack: Stack, resume: @escaping () -> Void) -> Bool {
        guard !isPro && stack.collaborators.count >= Self.freeCollaboratorLimit else { return true }
        present(.collaboratorLimit, resume: resume)
        return false
    }

    static func isItemLimitError(_ error: Error) -> Bool {
        error.localizedDescription.contains("Stacks Pro is required to add more than 15 items")
    }

    static func isCollaboratorLimitError(_ error: Error) -> Bool {
        error.localizedDescription.contains("Stacks Pro is required for more than 3")
    }

    func close() {
        gate = nil
        resumeAction = nil
        errorMessage = nil
    }

    func purchase(_ package: Package) async {
        guard !isBusy else { return }
        guard accountID != nil, isAccountLinked else {
            errorMessage = "Sign in to Stacks before subscribing."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return }
            await apply(result.customerInfo)
            if !usesTestStore, SupabaseConfiguration.fromAppBundle() != nil {
                _ = try await SupabaseProEntitlementService().sync()
            }
            if !isPro { errorMessage = "Your purchase is pending. Stacks Pro will unlock when Apple confirms it." }
        } catch {
            // RevenueCat completes and validates the App Store transaction.
            // Cancellation is harmless; other failures remain visible so a
            // member can retry or use Restore Purchases.
            let nsError = error as NSError
            if nsError.code != ErrorCode.purchaseCancelledError.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    func restore() async {
        guard !isBusy else { return }
        guard accountID != nil, isAccountLinked else {
            errorMessage = "Sign in to Stacks before restoring purchases."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            await apply(customerInfo)
            if !usesTestStore, SupabaseConfiguration.fromAppBundle() != nil {
                _ = try await SupabaseProEntitlementService().sync()
            }
            if !isPro { errorMessage = "No active Stacks Pro subscription was found for this Apple Account." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func package(for period: BillingPeriod) -> Package? {
        packages.first { $0.packageType == period.packageType }
    }
}

enum PriceAlertMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case anyDrop = "any_drop"
    case target
    var id: String { rawValue }
    var title: String { self == .anyDrop ? "Any price drop" : "Target price" }
}

enum PriceAlertStatus: String, Codable, Sendable {
    case active, paused
    case proRequired = "pro_required"
    case temporarilyUnavailable = "temporarily_unavailable"
}

struct PriceAlert: Identifiable, Codable, Hashable, Sendable {
    struct Product: Codable, Hashable, Sendable {
        let title: String
        let brand: String
        let removedBackgroundImagePath: String?
        let originalImagePath: String?
        let buyURL: String?
        let sourceURL: String?

        enum CodingKeys: String, CodingKey {
            case title, brand
            case removedBackgroundImagePath = "removed_background_image_path"
            case originalImagePath = "original_image_path"
            case buyURL = "buy_url"
            case sourceURL = "source_url"
        }
    }

    let id: UUID
    let stackItemID: UUID
    var mode: PriceAlertMode
    var targetPrice: Decimal?
    let currencyCode: String
    let baselinePrice: Decimal
    var currentPrice: Decimal
    var lowestPrice: Decimal
    var status: PriceAlertStatus
    var nextCheckAt: Date
    var lastCheckedAt: Date?
    var lastSuccessAt: Date?
    var lastError: String?
    let createdAt: Date
    var product: Product?

    enum CodingKeys: String, CodingKey {
        case id, mode, status
        case stackItemID = "stack_item_id"
        case targetPrice = "target_price"
        case currencyCode = "currency_code"
        case baselinePrice = "baseline_price"
        case currentPrice = "current_price"
        case lowestPrice = "lowest_price"
        case nextCheckAt = "next_check_at"
        case lastCheckedAt = "last_checked_at"
        case lastSuccessAt = "last_success_at"
        case lastError = "last_error"
        case createdAt = "created_at"
        case product = "stack_items"
    }

    var formattedCurrentPrice: String { Self.money(currentPrice, currency: currencyCode) }
    var formattedTargetPrice: String? { targetPrice.map { Self.money($0, currency: currencyCode) } }

    private static func money(_ value: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: value as NSDecimalNumber) ?? "\(currency) \(value)"
    }
}

struct PriceAlertEvent: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let alertID: UUID
    let previousPrice: Decimal
    let currentPrice: Decimal
    let currencyCode: String
    let createdAt: Date
    var readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case alertID = "alert_id"
        case previousPrice = "previous_price"
        case currentPrice = "current_price"
        case currencyCode = "currency_code"
        case createdAt = "created_at"
        case readAt = "read_at"
    }
}

enum PriceAlertError: LocalizedError {
    case proRequired
    case unavailable(String)
    var errorDescription: String? {
        switch self {
        case .proRequired: "Stacks Pro is required for more price alerts."
        case .unavailable(let message): message
        }
    }
}

@MainActor
@Observable
final class PriceAlertCenter {
    private(set) var alerts: [PriceAlert] = []
    private(set) var events: [PriceAlertEvent] = []
    private(set) var notificationsEnabled = true
    private(set) var isLoading = false
    var errorMessage: String?
    private var accountID: UUID?

    var unreadEventCount: Int { events.lazy.filter { $0.readAt == nil }.count }
    func alert(for itemID: UUID) -> PriceAlert? { alerts.first { $0.stackItemID == itemID } }

    func setAccount(_ id: UUID?) async {
        guard accountID != id else { return }
        accountID = id
        alerts = []; events = []; errorMessage = nil
        if id != nil { await refresh() }
    }

    func refresh() async {
        guard accountID != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let listing = try await SupabasePriceAlertService().list()
            alerts = listing.alerts
            events = listing.events
            notificationsEnabled = listing.notificationsEnabled
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func save(itemID: UUID, mode: PriceAlertMode, targetPrice: Decimal?, linkToken: UUID? = nil) async throws {
        do {
            try await SupabasePriceAlertService().save(itemID: itemID, mode: mode, targetPrice: targetPrice, linkToken: linkToken)
            await refresh()
        } catch {
            if error.localizedDescription.localizedCaseInsensitiveContains("Pro is required") {
                throw PriceAlertError.proRequired
            }
            throw PriceAlertError.unavailable(error.localizedDescription)
        }
    }

    func delete(_ alert: PriceAlert) async throws { try await SupabasePriceAlertService().delete(alertID: alert.id); await refresh() }
    func setPaused(_ paused: Bool, alert: PriceAlert) async throws {
        try await SupabasePriceAlertService().setPaused(paused, alertID: alert.id); await refresh()
    }
    func setNotificationsEnabled(_ enabled: Bool) async throws {
        try await SupabasePriceAlertService().setNotificationsEnabled(enabled)
        notificationsEnabled = enabled
    }
    func markRead(_ event: PriceAlertEvent) async {
        try? await SupabasePriceAlertService().markRead(eventID: event.id)
        if let index = events.firstIndex(where: { $0.id == event.id }) { events[index].readAt = .now }
    }

    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            return granted
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

}

struct PriceAlertEditorSheet: View {
    @Environment(PriceAlertCenter.self) private var center
    @Environment(StacksPro.self) private var pro
    @Environment(\.dismiss) private var dismiss
    let item: StackItem
    let stack: Stack
    @State private var mode: PriceAlertMode = .anyDrop
    @State private var targetText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var existing: PriceAlert? { center.alert(for: item.id) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Current price", value: item.formattedPrice)
                    if let checked = existing?.lastSuccessAt {
                        LabeledContent("Last checked", value: checked.formatted(date: .abbreviated, time: .shortened))
                    }
                } header: {
                    Text(item.title)
                }

                Section("Notify me when") {
                    Picker("Alert type", selection: $mode) {
                        ForEach(PriceAlertMode.allCases) { option in Text(option.title).tag(option) }
                    }
                    .pickerStyle(.inline)
                    if mode == .target {
                        HStack {
                            Text(item.currencyCode)
                            TextField("Target price", text: $targetText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if let existing {
                    Section {
                        Button(existing.status == .paused ? "Resume alert" : "Pause alert") {
                            Task {
                                try? await center.setPaused(existing.status != .paused, alert: existing)
                                dismiss()
                            }
                        }
                        Button("Delete alert", role: .destructive) {
                            Task { try? await center.delete(existing); dismiss() }
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .navigationTitle(existing == nil ? "Price alert" : "Edit price alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") { Task { await save() } }
                        .disabled(isSaving || (mode == .target && parsedTarget == nil))
                }
            }
            .onAppear {
                if let existing {
                    mode = existing.mode
                    targetText = existing.targetPrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
                }
            }
        }
    }

    private var parsedTarget: Decimal? {
        Decimal(string: targetText.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        let selectedMode = mode
        let selectedTarget = mode == .target ? parsedTarget : nil
        do {
            try await center.save(itemID: item.id, mode: selectedMode, targetPrice: selectedTarget, linkToken: stack.visibility == .publicLink ? stack.publicLinkToken : nil)
            dismiss()
            let status = await center.notificationAuthorizationStatus()
            if status == .notDetermined { _ = await center.requestNotificationPermission() }
        } catch PriceAlertError.proRequired {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                pro.present(.priceAlertLimit) {
                    Task {
                        try? await center.save(itemID: item.id, mode: selectedMode, targetPrice: selectedTarget, linkToken: stack.visibility == .publicLink ? stack.publicLinkToken : nil)
                        if await center.notificationAuthorizationStatus() == .notDetermined {
                            _ = await center.requestNotificationPermission()
                        }
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

struct PriceAlertsSettingsView: View {
    @Environment(PriceAlertCenter.self) private var center

    var body: some View {
        List {
            if center.isLoading && center.alerts.isEmpty {
                ProgressView("Loading alerts…")
            } else if center.alerts.isEmpty {
                ContentUnavailableView(
                    "No price alerts",
                    systemImage: "bell.badge",
                    description: Text("Open a saved product and tap Alert me. Your first alert is free.")
                )
            } else {
                Section("Watching") {
                    ForEach(center.alerts) { alert in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(alert.product?.title ?? "Saved product").font(.headline)
                                Spacer()
                                if alert.status == .proRequired {
                                    Text("PRO").font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(.thinMaterial, in: Capsule())
                                }
                            }
                            Text(alert.mode == .anyDrop ? "Any new low" : "Target \(alert.formattedTargetPrice ?? "")")
                                .font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Text(alert.formattedCurrentPrice)
                                Spacer()
                                Text(statusText(alert)).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { Task { try? await center.delete(alert) } }
                            if alert.status != .proRequired {
                                Button(alert.status == .paused ? "Resume" : "Pause") {
                                    Task { try? await center.setPaused(alert.status != .paused, alert: alert) }
                                }
                                .tint(.gray)
                            }
                        }
                    }
                }
            }

            if !center.events.isEmpty {
                Section("Recent drops") {
                    ForEach(center.events.prefix(20)) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Price dropped to \(money(event.currentPrice, currency: event.currencyCode))")
                            Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .task { if event.readAt == nil { await center.markRead(event) } }
                    }
                }
            }
        }
        .navigationTitle("Price Alerts")
        .task { await center.refresh() }
        .refreshable { await center.refresh() }
    }

    private func statusText(_ alert: PriceAlert) -> String {
        switch alert.status {
        case .active: "Active"
        case .paused: "Paused"
        case .proRequired: "Upgrade to resume"
        case .temporarilyUnavailable: "Retrying"
        }
    }

    private func money(_ value: Decimal, currency: String) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = currency
        return formatter.string(from: value as NSDecimalNumber) ?? "\(currency) \(value)"
    }
}

struct NotificationSettingsView: View {
    @Environment(PriceAlertCenter.self) private var center
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                Toggle("Price drops", isOn: Binding(
                    get: { center.notificationsEnabled },
                    set: { enabled in Task { try? await center.setNotificationsEnabled(enabled) } }
                ))
            } footer: {
                Text("Price checks continue even when notifications are off. Changes remain visible in Price Alerts.")
            }
            Section("iPhone permission") {
                LabeledContent("Status", value: authorizationLabel)
                if authorizationStatus == .notDetermined {
                    Button("Allow notifications") { Task { _ = await center.requestNotificationPermission(); await updateStatus() } }
                } else if authorizationStatus == .denied {
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .task { await updateStatus() }
    }

    private var authorizationLabel: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
    private func updateStatus() async { authorizationStatus = await center.notificationAuthorizationStatus() }
}

struct StacksProPaywall: View {
    var body: some View {
        // The dashboard template still contains unrelated sample pricing and
        // Family Sharing claims. Use a native RevenueCat-backed purchase view
        // until a reviewed, published Stacks paywall replaces that template.
        StacksProFallbackPaywall()
    }
}

private struct StacksProFallbackPaywall: View {
    @Environment(StacksPro.self) private var pro
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod: StacksPro.BillingPeriod = .annual
    private var selectedPackage: Package? { pro.package(for: selectedPeriod) }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 18) {
                        HStack {
                            Spacer()
                            Button("Continue free", systemImage: "xmark") { pro.close(); dismiss() }
                                .labelStyle(.iconOnly)
                                .accessibilityLabel("Continue free")
                                .foregroundStyle(.black)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(.top, 20)

                        Spacer(minLength: 24)
                        Text((pro.gate ?? .settings).title)
                            .font(.system(size: 42, weight: .semibold))
                            .tracking(-2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.75)
                        Text(pro.gate?.message ?? "Make more room for everything you love.")
                            .font(.system(size: 16))
                            .foregroundStyle(.black.opacity(0.68))
                            .multilineTextAlignment(.center)
                        VStack(alignment: .leading, spacing: 14) {
                            benefit("Track up to 25 product prices")
                            benefit("Unlimited items in every Stack")
                            benefit("Bring more than 3 people into a Collab")
                        }
                        .padding(.vertical, 26)
                        Spacer(minLength: 24)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .frame(minHeight: max(geometry.size.height * 0.55, 400))
                    .frame(maxWidth: .infinity)
                    .background {
                        ProCutoutField()
                    }

                    VStack(spacing: 14) {
                        planButton(period: .annual, detail: "Billed yearly")
                        planButton(period: .monthly, detail: "Billed monthly")
                        Button {
                            guard let selectedPackage else { return }
                            Task { await pro.purchase(selectedPackage) }
                        } label: {
                            HStack {
                                if pro.isBusy { ProgressView().tint(.white) }
                                Text("Continue with Stacks Pro")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .background(.black, in: Capsule())
                        .disabled(selectedPackage == nil || pro.isBusy)

                        if pro.packages.isEmpty {
                            Text("Plans aren't available right now. You can continue free and try again later.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        Text(renewalText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if let errorMessage = pro.errorMessage {
                            Text(errorMessage).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                        }
                        HStack(spacing: 18) {
                            Button("Restore Purchases") { Task { await pro.restore() } }
                            Link("Terms of Use", destination: StacksLegalAgreement.termsURL)
                            Link("Privacy Policy", destination: StacksLegalAgreement.privacyURL)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(maxWidth: 480)
                }
            }
            .background(.white)
            .onChange(of: pro.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            .onChange(of: pro.packages.count) { _, _ in
                if pro.package(for: selectedPeriod) == nil, let first = pro.packages.first {
                    selectedPeriod = first.packageType == .annual ? .annual : .monthly
                }
            }
            .task { if pro.currentOffering == nil { await pro.start() } }
        }
    }

    private var renewalText: String {
        guard let selectedPackage else { return "Your App Store will show the final price before you subscribe." }
        return "\(selectedPackage.storeProduct.localizedPriceString) per \(selectedPeriod == .annual ? "year" : "month"). Renews automatically until canceled in Apple Settings."
    }

    private func benefit(_ title: String) -> some View {
        Label(title, systemImage: "checkmark")
            .font(.system(size: 15, weight: .medium))
    }

    @ViewBuilder
    private func planButton(period: StacksPro.BillingPeriod, detail: String) -> some View {
        if let package = pro.package(for: period) {
            Button { selectedPeriod = period } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(period == .annual ? "Annual" : "Monthly")
                            .font(.system(size: 16, weight: .semibold))
                        Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(package.storeProduct.localizedPriceString)
                            .font(.system(size: 19, weight: .bold))
                        Text(period == .annual ? "per year" : "per month")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: selectedPeriod == period ? "largecircle.fill.circle" : "circle")
                }
                .padding(15)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(selectedPeriod == period ? .black : .clear, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ProCutoutField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Cutout: Identifiable {
        let id: String
        let imageName: String
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let rotation: Double
        let phase: Double
    }

    private let cutouts: [Cutout] = [
        Cutout(id: "shoe", imageName: "OnboardingSambaShoe", x: 0.11, y: 0.18, size: 126, rotation: -13, phase: 0.2),
        Cutout(id: "lamp", imageName: "OnboardingLampOrangeMushroom", x: 0.82, y: 0.15, size: 112, rotation: 7, phase: 1.4),
        Cutout(id: "hat", imageName: "OnboardingRamblinCap", x: 0.91, y: 0.47, size: 105, rotation: 12, phase: 2.1),
        Cutout(id: "shirt", imageName: "OnboardingMemorialShirt", x: 0.08, y: 0.54, size: 128, rotation: -9, phase: 3.0),
        Cutout(id: "record", imageName: "StickerVinyl", x: 0.29, y: 0.80, size: 82, rotation: -8, phase: 3.8),
        Cutout(id: "taxi", imageName: "StickerYellowTaxi", x: 0.73, y: 0.79, size: 105, rotation: 9, phase: 4.7),
        Cutout(id: "lipstick", imageName: "StickerLipstick", x: 0.52, y: 0.09, size: 70, rotation: 10, phase: 5.5),
        Cutout(id: "eight-ball", imageName: "StickerEightBall", x: 0.50, y: 0.91, size: 66, rotation: -7, phase: 6.3)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { proxy in
                ZStack {
                    Color.white

                    ForEach(cutouts) { cutout in
                        let horizontalDrift: CGFloat = reduceMotion ? 0 : CGFloat(sin(time * 0.72 + cutout.phase) * 8)
                        let verticalDrift: CGFloat = reduceMotion ? 0 : CGFloat(cos(time * 0.86 + cutout.phase) * 12)
                        let turn = reduceMotion ? 0 : sin(time * 0.48 + cutout.phase) * 3

                        Image(cutout.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: cutout.size, height: cutout.size)
                            .rotationEffect(.degrees(cutout.rotation + turn))
                            .shadow(color: .black.opacity(0.13), radius: 8, x: 0, y: 6)
                            .position(
                                x: proxy.size.width * cutout.x + horizontalDrift,
                                y: proxy.size.height * cutout.y + verticalDrift
                            )
                    }

                    RadialGradient(
                        colors: [.white.opacity(0.96), .white.opacity(0.76), .white.opacity(0.10)],
                        center: .center,
                        startRadius: 20,
                        endRadius: min(proxy.size.width, proxy.size.height) * 0.62
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
