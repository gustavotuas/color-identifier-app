# WaveColorAI — ProSuite Global Edition (Sources Only)

Xcode 26 • Swift 6 • iOS 18 SDK.

## Plans & Trial
- Weekly: $5.99 — no trial
- Monthly: $14.99 — 3-day free trial — launch 50% OFF (regular $29.99)
- Yearly: $59.99 — 3-day free trial — launch 50% OFF (regular $119.99)

## What's inside
- SwiftUI app skeleton (Tabs, Onboarding, Camera, Photos, Browse, Discover, Profile)
- **StoreKit 2 paywall** with monthly/yearly trial + 50% launch badges
- **AI/AR stubs**: Smart Match, Color Coach, Auto-Lighting Correction, AR Preview, Magic Replace, Export (PDF/PNG)
- **36 localizations** folders with `Localizable.strings` (EN/ES translated; others default to EN)

## Quick Start
1) Create a NEW SwiftUI app project named "WaveColorAI" (Bundle ID: com.yourcompany.wavecolorai).
2) Close Xcode. Copy these folders into your new project:
   - Sources/
   - Resources/
   - Localization/
   - StoreKit/
3) Reopen Xcode → Target → Signing & Capabilities → add **In-App Purchase**.
4) Build Settings: ensure Swift 6, iOS 16+ deployment target.
5) Scheme → Run → Options → **StoreKit Configuration**: select `StoreKit/LaunchSale.storekit`.
6) Run on a real iPhone (camera/AR).

## Product IDs (use the same IDs in App Store Connect)
- com.yourcompany.wavecolorai.pro.weekly
- com.yourcompany.wavecolorai.pro.monthly
- com.yourcompany.wavecolorai.pro.yearly
