# AI chat and subscription removal

DONE on staging — accepted by Tom on 2026-10-02. Implemented, deployed and verified within the scope below; remaining verification gaps are recorded separately.

Live UI verification: Vietnamese dashboard and populated Test v2 booking list/detail/return navigation on mobile, plus desktop booking list. No AI launcher, chat or purchase controls remain, and navigation is unobstructed. Screenshots: `.dart_tool/ai-removal-screenshots/`. English and enlarged-text live checks remain unverified; automated core regression coverage is separate. No real subscriptions were cancelled.

The six legacy URLs remain as inert compatibility responses (`feature_retired`, HTTP 410 for the webhook). They bind no Gemini/RevenueCat secrets and cannot run AI extraction, commit drafts, refresh entitlements or process purchases. Historical records remain server-only. Legacy backend modules/tests remain in source for historical regression coverage but are disconnected from all deployed exports.

Verification: 188 server tests passed. All six retired endpoints were verified live on staging with disposable identities, including refusal to commit an old draft and HTTP 410 from the billing webhook. Full Flutter run finished with 331 passes and one file-load failure: a tenant test imported an auth helper from the removed AI test. The helper was moved to test/support/auth_fake.dart without changing tenant assertions; both dependent files then passed all five targeted checks. Analysis completed with no errors. The first web build reused a stale purchase-plugin registrant; its generated build cache was cleared and the fresh registrant has no purchase SDK reference. The subsequent web build and staging deployment succeeded; live navigation checks passed as described above. English and enlarged-text live checks remain open.

## Scope

Remove the floating AI chat, paid-plan/restore-purchase screens, cloud AI extraction/import, AI service registration, and purchase SDK dependency. Normal booking, tenant, invoice and spreadsheet workflows must keep working under their existing role permissions. Local classification models are a separate future design decision, not a replacement promised by this change.

Retire all six public AI/billing endpoints: aiChat, aiUsage, aiImportPreview, aiImportCommit, aiSyncSubscription and revenueCatWebhook. Removing an export alone does not remove an already deployed endpoint: the staging release must explicitly retire or disable those deployed endpoints and verify old-client calls cannot generate paid requests or commit old drafts. Preserve historical entitlement, receipt, request and draft records behind current server-only rules; account deletion retains its existing cleanup behavior.

External subscription cancellation, refunds and production provider-secret deletion are not part of this staging software change. No external billing subscriptions should be created while testing.

## Situations and checks

- Signed out, owner, limited co-owner, staff, suspended/revoked and unrelated accounts: no chat/paywall entry, unchanged core permission checks.
- Legacy and v2 organizations; desktop and phone entry routes; returning from dialogs must not reinstall the chat overlay.
- Free, paid, expired and missing historical entitlement records must not gate core workflows or trigger billing refresh.
- Existing old-client endpoint requests, draft commits, webhook retries and concurrent calls must fail safely without provider requests or writes.
- Startup, dashboard, organization, room and booking navigation; empty/loading/error states and all buttons formerly obscured by the overlay.
- English/Vietnamese, narrow phone, landscape, desktop, normal/130%/200% text. Actual screenshots must be inspected for affected populated screens.
- Targeted removal regression tests, full sequential Flutter suite (shared app root changes), server suite, then live staging checks including retired endpoint behavior.

Inventory: lib/main.dart installs ChatOverlayManager and AIAgentService; lib/widgets/chat/chat_manager.dart owns entry/usage/chat; lib/screens/ai_chat owns import and purchases; functions/index.js binds Gemini and RevenueCat secrets; functions/staging_index.js substitutes provider-disabled handlers. Deployment identity tests and release tools currently special-case the old endpoints and must be updated together.

## Later clean-up (Tom, 2026-10-02)

After all client features, the v2 move and a new store release everyone has installed: delete the dead `functions/ai.js`, `functions/ai_import.js`, `functions/subscriptions.js` and their tests; remove the six retired stub endpoints and delete them from the deployed project explicitly (update `functions/test/staging_identity.test.js`); remove production Gemini/RevenueCat secrets and cancel any provider subscription. Tracked in CLIENT_ROADMAP.md "Start here" item 5.
