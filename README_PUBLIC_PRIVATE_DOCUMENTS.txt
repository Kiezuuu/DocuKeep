DOCUKEEP PUBLIC / PRIVATE DOCUMENT VISIBILITY UPDATE

WHAT CHANGED
- My Documents is now a Document Library that includes your own documents and documents other signed-in DocuKeep users have made public.
- Added filters: All visible documents, My documents, and Public documents.
- Each document displays a Public or Private label.
- Owners can switch their own document between Public and Private from the document card or preview panel.
- New uploads default to Private.
- Private documents are not listed to other ordinary users. Public documents can be viewed/downloaded by authenticated DocuKeep users.
- Existing explicit user/group shares continue to be supported.

IMPORTANT VISIBILITY NOTES
- Public means available to signed-in DocuKeep accounts; it does not publish the file to anonymous internet visitors.
- The existing staff/admin review role retains its existing administrative access. This update does not remove staff moderation permissions.
- Existing documents are set to Private by default when the migration runs. Owners may make selected documents public afterward.

SUPABASE SETUP REQUIRED
1. Open Supabase Dashboard > SQL Editor.
2. Run docukeep_public_private_documents_migration.sql AFTER your existing DocuKeep migrations, including docukeep_migration.sql and DocuKeep-Classroom-Sharing.sql.
3. Deploy the updated index.html to your existing hosting location.
4. Sign in with two test accounts. Upload a document in account A and confirm it starts Private. Make it Public, then confirm account B can see and open it in Document Library. Switch it back to Private and confirm account B can no longer see or open it.

The SQL migration adds the is_public column and the row/storage access policies needed for the UI. Do not skip the SQL step: the frontend alone cannot enforce document privacy securely.

TESTING LIMITATION
The code and archive were checked locally for JavaScript syntax and ZIP integrity. A live Supabase database, Storage policy, and two-account browser test were not available here, so complete live behavior still needs the setup/test steps above.
