# LendMosaic

Native Swift 6 / iOS 18.6+ independent application. Open LendMosaic.xcodeproj and run the LendMosaic scheme on iPhone. No third-party runtime dependencies. Local JSON uses atomic writes and refuses to overwrite corrupt data; errors are shown. To load demonstration records, use Settings → Load sample data on an empty collection. Real first launch is empty.

Languages: English, Japanese, Korean, Spanish, French, German, Brazilian Portuguese, Italian. English fallback. Settings persist language and System/Light/Dark preference.

Architecture: ProductRoot and task-specific Views, observable model with business operations, generic Repository for JSON, String Catalog, semantic design tokens in Common.swift. Photos, tracking, location, login, ads and IAP are absent. JSON export is initiated by the user.

Free app. Tile estimates are planning aids; proofreading tracks entered corrections; loan dates do not send reminders. Tests and source are included. Code signing, real devices, signed CloudKit Production and App Store work remain manual.
