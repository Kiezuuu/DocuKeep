DOCUKEEP PREMIUM SUBSCRIPTION UPDATE

FILES
- index.html: updated complete DocuKeep page with Premium plan choices, user request submission, current subscription display, and staff activation controls.
- add_subscription_migration.sql: run once in Supabase SQL Editor AFTER your existing DocuKeep setup and docukeep_migration.sql.

SETUP
1. Back up your current index.html.
2. In Supabase Dashboard > SQL Editor, run add_subscription_migration.sql.
3. Replace the website's current index.html with this package's index.html and publish/deploy it.
4. Sign in as an approved staff account. Open Staff Administration > Premium subscription requests.
5. When a request arrives, contact the user using the email shown, collect payment directly, verify payment, select the correct duration, and click Confirm payment & activate.
6. The user's existing Student/Teacher identity role is not changed. Premium is managed as a separate entitlement so the account's sign-in type and staff permissions remain safe.

SUBSCRIPTION PERIODS
- Week: 7 days
- Month: 1 calendar month
- Year: 1 calendar year
The period begins when staff activates the plan. The UI checks the expiry timestamp. The SQL migration includes expire_docukeep_subscriptions(); schedule it daily with Supabase Cron if available so expired rows are also marked Free/inactive in the database.

IMPORTANT
- Payment is manual and outside DocuKeep. No payment gateway is connected.
- No prices or admin payment details were supplied, so the page says the administrator will provide them after the request.
- The database quota is 128 GiB for an active Premium entitlement. The existing per-file upload limit remains 25 MB.
- Confirm your Supabase project's actual storage capacity/billing supports the 128 GiB allowance; a database quota cannot increase the provider's physical storage allocation.
- The premium page lists the requested feature set. This update adds the subscription request/activation/expiry workflow and the database storage-quota guard; it does not complete all premium feature implementations such as duplicate-file deletion or full group-sharing UI.
