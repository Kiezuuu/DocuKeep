DOCUKEEP SUBSCRIPTION + PAYMENT REQUEST UPDATE

PRICES
- 1-Year Subscription: PHP 100 per year (about PHP 8.33/month)
- 1-Month Subscription: PHP 50 per month
- 1-Week Subscription: PHP 25 per week

PAYMENT DISPLAY
- GCash and Maya are displayed as payment options.
- Placeholder account name: Aimerck Bruznyr Remollo
- Placeholder number: 09XX XXX XXXX
- QR boxes are non-working placeholders, not scannable payment codes. Replace them with your actual GCash/Maya numbers and QR images before publishing or accepting payments.

USER FLOW
1. User selects a subscription plan.
2. User pays using the confirmed official GCash/Maya account details.
3. User enters the required payment Reference ID and uploads a JPG, PNG, or PDF receipt (max 5 MB).
4. The request, amount, reference ID, receipt path, and status are stored in Supabase.
5. Staff sees requests in Staff Administration, opens the receipt, and accepts or denies the request. Staff can send a message explaining the decision or asking for more information.
6. When staff accepts, Premium is activated for 7 days, 1 month, or 1 year. A denied request shows the staff message to the user.

INSTALLATION
1. Back up the Supabase project.
2. Run add_subscription_payments_migration.sql in Supabase SQL Editor. This assumes the base DocuKeep migration and public.is_docukeep_staff() already exist.
3. Replace the deployed site's index.html with this package's index.html and publish it.
4. Replace the placeholder payment details and QR boxes with the real GCash/Maya details before asking users to pay.
5. Test a request using a test account, then review it using an approved staff account.

IMPORTANT
- This is manual payment verification. No GCash/Maya payment gateway or automatic payment confirmation is connected.
- The SQL has not been run against the live Supabase project. You must run it yourself.
- This update does not complete every Premium feature or guarantee 128 GB storage quota enforcement. The existing file upload limit remains 25 MB per file unless separately changed.
- Never put a Supabase service_role key in index.html.
