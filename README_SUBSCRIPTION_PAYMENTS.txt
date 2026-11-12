DOCUKEEP PREMIUM SUBSCRIPTION + PAYMENT REQUEST UPDATE

FILES
- index.html: complete updated DocuKeep frontend based on the latest available review-comments version.
- add_subscription_payments_migration.sql: additive Supabase migration for payment requests, private receipt storage, staff review/message RPCs, and subscription expiry.

PRICING SHOWN IN THE APP
- 1-Year Subscription: PHP 999 per year (equivalent to PHP 83.25/month)
- 1-Month Subscription: PHP 99 per month
- 1-Week Subscription: PHP 39 per week

INSTALLATION
1. Back up your Supabase project first.
2. In Supabase SQL Editor, run add_subscription_payments_migration.sql.
   This migration assumes the existing DocuKeep setup and docukeep_migration.sql have already been run, including the docukeep_entitlements table and is_docukeep_staff() helper.
3. Replace the deployed site's index.html with the included index.html.
4. Publish the updated site (for GitHub Pages, commit and push the updated index.html).
5. Sign in using a student/teacher account, open Premium Plan, choose a plan, and upload a test receipt.
6. Sign in using an approved staff account, open Staff Administration, and review the Premium subscription and payment requests section.

WORKFLOW
- Student/teacher selects a plan and uploads a JPG, PNG, or PDF receipt (max 5 MB).
- The receipt is stored in a private Supabase bucket; it is not publicly accessible.
- The admin can open the receipt, send a transaction message, accept and activate Premium, or reject with a reason.
- On approval, the database activates the Premium entitlement and calculates the expiry: 7 days, 1 month, or 1 year.
- The user's account role remains student/teacher. Premium is a separate entitlement.
- The entitlement's expiry is checked by docukeep_has_active_premium(); expire_docukeep_premium_subscriptions() can be scheduled daily to mark expired rows as Free.

IMPORTANT
- This is a manual payment verification workflow. No GCash, Maya, bank API, payment gateway, or automatic payment confirmation is connected.
- Set and communicate the official payment instructions/contact details separately. No payment account or admin contact was invented in this update.
- This update adds the subscription request and payment review workflow. It does not by itself complete every Premium feature's UI or guarantee a 128 GB quota at the Supabase Storage/billing level. The existing bucket in the current migration still has a 25 MB per-file cap.
- The SQL has not been run against your live Supabase project. Test first in a backup/staging project. Never put a service_role key in index.html.
