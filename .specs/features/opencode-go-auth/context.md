# OpenCode Go Dual Authentication Context

**Gathered:** 2026-10-19  
**Spec:** `.specs/features/opencode-go-auth/spec.md`  
**Status:** Ready for design

---

## Feature Boundary

Add per-account OAuth device authorization for OpenCode Go, retain API-key authentication, refresh and store each method safely, and keep the existing quota UI working. Do not read or modify OpenCode CLI V2 credentials. Removing an OAuth connection is a local disconnect, not a remote Console logout.

---

## Implementation Decisions

### Authentication choice

- Browser authorization is the primary path for new OpenCode accounts.
- API key stays available as an explicit alternative.
- Each account stores its own authentication method and credential; existing accounts default to API key.
- Reauthentication keeps the same method, workspace, account UUID, label, and displayed quota window unless the user explicitly replaces the account.

### OAuth session lifecycle

- The limit-bar starts a separate Console device flow with client ID `limit-bar`; it never imports a CLI session.
- The UI opens the official verification URL, displays the user code, and lets the user cancel while polling.
- Only HTTPS URLs on `opencode.ai` are allowed for browser authorization.
- OAuth secrets live in the limit-bar Keychain; account state contains only the method discriminator.
- Refresh uses the latest rotated token and is serialized per account.
- Removing an OAuth account deletes local secrets and warns that the Console session remains valid remotely.

### User experience

- Existing English source keys are localized in all three project languages.
- Failed authorization or Keychain writes do not create a seemingly connected account.
- 401/403 on OAuth offers reconnect; API-key auth failure offers key replacement.
- Last-good quota remains visible while auth needs repair.

### Agent's Discretion

- Use an actor-backed auth manager and injected `URLSession`/credential store to isolate networking and token rotation.
- Keep device flow and token refresh UI state in SwiftUI settings; use the existing `OpenURLAction` to open the verified URL.
- Use a versioned Codable envelope for OAuth tokens in a single Keychain item, keyed by account UUID.
- Default a legacy missing auth discriminator to `.apiKey` without rewriting old persisted state until a normal save occurs.

### Declined / Undiscussed Gray Areas → Assumptions

- **Remote revocation:** no public revocation API was found. Delete local tokens only and warn before removal.
- **No-plan / unsupported response:** preserve existing unauthorized/network/parse handling; never infer zero usage from missing quota fields.
- **Device-flow cancellation on server:** no cancel endpoint is documented; stop local polling and let the server code expire.
- **Multiple accounts/workspaces:** use separate credential items per account; account labels remain the user's presentation choice.

---

## Specific References

- User is on OpenCode CLI V2 and cannot create the key required by the current limit-bar form.
- User approved both authentication methods, browser-first setup, same-method reauthentication, and local-only disconnect warning.
- Live test with the user's manual approval: device-code JSON request accepted; OAuth Bearer returned HTTP 200 from `/zen/go/v1/usage` without `x-org-id`; a single refresh returned a new usable access token. Temporary credentials and response files were deleted.

## Deferred Ideas

- Console UI link for revoking a device session, if OpenCode documents a supported route.
- Automatically detect whether a Go subscription is active before starting OAuth.
- Import or synchronize a CLI V2 session (explicitly out of scope and not recommended).
