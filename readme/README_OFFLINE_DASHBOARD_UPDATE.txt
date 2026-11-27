DOCUKEEP — OFFLINE DASHBOARD UPDATE

What changed
- Offline login now opens the normal DocuKeep application shell and Dashboard instead of hiding the sidebar and forcing the separate Offline Workspace page.
- The Dashboard and My Documents pages are populated only from encrypted documents already cached on this device for the currently authorized account.
- Cached documents can be opened from the normal document list. Opening a cached document reads its locally encrypted blob; it does not request a Supabase URL.
- Cloud-only navigation destinations are disabled while offline. Upload remains available through the existing local pending-upload queue.
- The profile menu's logout action exits the local offline session without calling Supabase Auth.
- Storage quota refresh is skipped while offline.
- Newly cached document metadata now also stores category, owner display name, and visibility metadata for a more complete local document list.

What was intentionally not changed
- Supabase online sign-in and normal online navigation.
- Existing IndexedDB database/store names and encrypted offline file format.
- Existing pending-upload queue and synchronization implementation.
- Supabase database schema and Edge Function.

Deployment and testing
1. Publish this project to Cloudflare Pages.
2. While online, sign in and cache documents using the existing Save for offline action.
3. Confirm those documents appear in Dashboard / My Documents while online.
4. In Chrome DevTools, enable Network > Offline and use Continue Offline.
5. Confirm the normal DocuKeep shell appears, cached documents are listed, and Open cached file downloads from local storage.
6. Confirm cloud-only navigation is disabled and queued uploads remain queued until online sign-in resumes.

Note
This is a frontend change. It does not repair an invalid Ed25519 authorization signature. Offline login still requires a valid, unexpired authorization record. Existing cached documents encrypted with a different key or older incompatible format cannot be assumed readable.
