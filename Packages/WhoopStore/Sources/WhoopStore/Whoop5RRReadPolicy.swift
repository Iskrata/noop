import GRDB
import WhoopProtocol

extension WhoopStore {
    /// The transports a WHOOP 5 window may be SCORED through, as a SQL list.
    ///
    /// One constant rather than a literal per query. `rrIntervals` pins a window to the lowest of these
    /// present, and `firstScorableWhoop5RRTimestamp` reports when the first of them was banked, so the
    /// day the app tells a wearer its scoring begins is derived from the same set the scoring uses. Two
    /// literals would let those drift apart silently, and the drift would show as an explanation that
    /// names the wrong date. Type-40 live (6) is deliberately absent: it is a labelling channel that
    /// standard BLE (7) already covers beat for beat.
    static let scorableWhoop5Channels = "(5, 7)"

    /// Fork: score a WHOOP 5 window from its unlabelled legacy rows when it has no verified transport.
    ///
    /// Upstream withholds them because some installs banked mixed units under NULL. This strap's legacy
    /// rows (2026-08-24 → 09-11) were checked against its labelled ones on the phone DB copy of 09-19:
    /// same range (333–2400 ms vs 325–2400), same mean (1006 vs 1010 ms) and the same density
    /// (~39.6k vs ~38k beats a day), so they are one transport in ms. Without them those nights stage
    /// with no breathing term (deep/REM 11.5/15.3 % vs WHOOP's 19.8/28.7 %) and have no HRV or Charge.
    /// A window that has a labelled transport still reads only that transport. Mutable only so the
    /// upstream policy tests can pin the strict behaviour; nothing in the app writes it.
    nonisolated(unsafe) public static var scoresUnlabelledWhoop5Legacy = true

    /// The earliest beat this device has banked that the unit policy can actually score, or nil when it
    /// has none at all.
    ///
    /// Cheap and device-level, not per-day: one indexed MIN over the beats already on disk. Carries the
    /// same suspect-timestamp exclusion as the scoring read (#1073), so it cannot name a day that
    /// scoring would then refuse. The caller turns it into a local day key; the calendar is the app's
    /// policy, not the store's.
    public func firstScorableWhoop5RRTimestamp(deviceId: String) async throws -> Int? {
        // Fork: every recorded beat is scorable (see `scoresUnlabelledWhoop5Legacy`).
        if Self.scoresUnlabelledWhoop5Legacy { return try await firstRecordedRRTimestamp(deviceId: deviceId) }
        return try syncRead { db in
            try Int.fetchOne(db, sql: """
                SELECT MIN(ts) FROM rrInterval
                WHERE deviceId = ? AND srcChannel IN \(Self.scorableWhoop5Channels)
                AND (tsSuspect IS NULL OR tsSuspect <> 1)
                """, arguments: [deviceId])
        }
    }

    /// The earliest beat this device has banked AT ALL, labelled or not, or nil when it has none.
    ///
    /// The lower bound on the "cannot be scored" explanation: it is what separates history this strap
    /// actually recorded from history imported from somewhere else, and only the former can have lost
    /// anything to a labelling change. Same shape and same suspect exclusion as the scorable read above.
    public func firstRecordedRRTimestamp(deviceId: String) async throws -> Int? {
        try syncRead { db in
            try Int.fetchOne(db, sql: """
                SELECT MIN(ts) FROM rrInterval
                WHERE deviceId = ? AND (tsSuspect IS NULL OR tsSuspect <> 1)
                """, arguments: [deviceId])
        }
    }

    /// Whether the strict WHOOP 5 read policy withheld this exact window solely because it contains
    /// unlabelled, non-quarantined legacy rows and no verified scoring transport. This is deliberately
    /// narrower than "the R-R read was empty": an unworn night, WHOOP 4, another brand, and a labelled
    /// but insufficient transport all return false and therefore remain ordinary current-score outcomes.
    public func legacyWhoop5RRWithheld(deviceId: String, from: Int, to: Int,
                                       unlabelledAliasOfWhoop5: Bool = false) async throws -> Bool {
        // Fork: legacy rows are scored (see `scoresUnlabelledWhoop5Legacy`), so nothing is withheld.
        if Self.scoresUnlabelledWhoop5Legacy { return false }
        return try syncRead { db in
            guard try Self.isWhoop5RRSource(db: db, deviceId: deviceId,
                                            unlabelledAliasOfWhoop5: unlabelledAliasOfWhoop5) else {
                return false
            }
            return try Bool.fetchOne(db, sql: """
                SELECT
                  EXISTS(SELECT 1 FROM rrInterval
                         WHERE deviceId = :d AND ts >= :f AND ts <= :t
                           AND srcChannel IS NULL
                           AND (tsSuspect IS NULL OR tsSuspect <> 1))
                  AND NOT EXISTS(SELECT 1 FROM rrInterval
                         WHERE deviceId = :d AND ts >= :f AND ts <= :t
                           AND srcChannel IN \(Self.scorableWhoop5Channels)
                           AND (tsSuspect IS NULL OR tsSuspect <> 1))
                """, arguments: ["d": deviceId, "f": from, "t": to]) ?? false
        }
    }

    /// Shared by RR reads and consumers whose cached/union reads must obey the same owner policy.
    public func isWhoop5RRSource(deviceId: String, unlabelledAliasOfWhoop5: Bool = false) async throws -> Bool {
        try syncRead { try Self.isWhoop5RRSource(db: $0, deviceId: deviceId,
                                              unlabelledAliasOfWhoop5: unlabelledAliasOfWhoop5) }
    }

    static func isWhoop5RRSource(db: Database, deviceId: String,
                               unlabelledAliasOfWhoop5: Bool = false) throws -> Bool {
        let row = try Row.fetchOne(db, sql: "SELECT model, brand FROM pairedDevice WHERE id = ?",
                                   arguments: [deviceId])
        let model: String? = row?["model"]
        let brand: String? = row?["brand"]
        // Only unknown identity needs wire evidence. Avoid scanning tagged rows for a known family.
        let knownFamily = DeviceFamily.confirmedRegistryFamily(model: model, brand: brand)
        let nonWhoop = brand.map { !$0.isEmpty && $0.lowercased() != "whoop" } ?? false
        var tagged = false
        if knownFamily == nil && !nonWhoop {
            tagged = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM rrInterval WHERE deviceId = ? AND srcChannel IN (5, 6, 7))
                """, arguments: [deviceId]) ?? false
            // Re-pairing can leave legacy rows under the canonical alias while callers still hold
            // that old ID. Resolve its active strap here so sleep edits and ordinary reads agree.
            // Physical owners and confirmed WHOOP 4 history never inherit another strap's policy.
            if !tagged && !unlabelledAliasOfWhoop5 && deviceId == "my-whoop",
               let active = try String.fetchOne(db, sql: DeviceRegistryStore.activeDeviceIdSQL),
               active != deviceId {
                tagged = try isWhoop5RRSource(db: db, deviceId: active)
            }
        }
        return Whoop5RR.usesCanonicalSource(model: model, brand: brand, hasTaggedIntervals: tagged || unlabelledAliasOfWhoop5)
    }
}
