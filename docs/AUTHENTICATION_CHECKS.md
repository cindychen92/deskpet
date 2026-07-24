# Authentication and private pet checks

Run these checks against a non-production Firebase project after enabling the
Anonymous and Google authentication providers and deploying the checked-in
Firestore and Storage rules.

## Setup

1. Add an explicit Boolean `isPublic` field to each document in `pets`.
2. Keep user-owned images under `users/<owner-uid>/pets/<pet-id>/` regardless
   of visibility; Simba may remain under `resources/simba/`.
3. Replace the local `GoogleService-Info.plist` with a freshly downloaded file
   that contains `CLIENT_ID` and `REVERSED_CLIENT_ID`.
4. Build and launch the signed macOS app.

## Manual acceptance matrix

| Scenario | Expected result |
| --- | --- |
| Fresh launch | No login prompt; normal pet actions work. |
| Anonymous pet menu | Public pets are selectable and “Sign in with Google” is shown. |
| Anonymous settings | Upload controls are replaced with Google sign-in guidance. |
| Cancel Google sign-in | The app remains anonymous and usable. |
| Failed Google sign-in | A localized failure is shown and the anonymous session survives. |
| Successful Google sign-in | Account identity and sign-out appear; owned pets and upload controls refresh without restart. |
| Private upload | Images are written under `users/<uid>/pets/<pet-id>/` and metadata has the same `ownerUid` with `isPublic: false`. |
| Visibility change | Changing `isPublic` changes other users’ read access without moving Storage files; only the owner retains write access. |
| Different Google account | The first account’s metadata and images cannot be read or selected. |
| Sign out on a public pet | Public pets remain available and the selected public pet remains active. |
| Sign out on a private pet | The app falls back to Simba or another public pet and explains the change. |
| Direct anonymous/private reads | Firestore metadata and Storage images are denied by deployed rules. |
| English and Simplified Chinese | New menu, settings, success, failure, and fallback copy is localized. |
