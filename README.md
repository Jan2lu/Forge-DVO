# Forge Davao gym app

Dues, reminders, PRs, workout of the day, class schedule and reservations, announcements, and a metcon leaderboard.
Members sign up with email, coaches approve them. Hosted free on GitHub Pages, data in Supabase.

## Files
- `index.html` the whole app
- `config.js` your Supabase URL and anon key
- `schema.sql` tables, access rules and the "log once" rule

## Setup (about 15 minutes)

### 1. Supabase
1. Create a project at supabase.com.
2. Open **SQL Editor**, paste all of `schema.sql`, and run it.
3. Open **Authentication > Providers > Email**. Keep email sign-in on. Turn **Confirm email** off if you want members to get in without a confirmation email (coach approval is still required).
4. Open **Authentication > URL Configuration** and set **Site URL** to your GitHub Pages address (step 2 below).
5. Open **Project Settings > API**. Copy the **Project URL** and the **anon public** key.

### 2. GitHub Pages
1. Put these files in a new GitHub repo.
2. Edit `config.js` and paste your URL and anon key. The anon key is public by design. Do not paste the `service_role` key anywhere.
3. In the repo, open **Settings > Pages**, choose **Deploy from a branch**, branch `main`, folder `/ (root)`.
4. Your app is at `https://YOUR-NAME.github.io/REPO-NAME/`.

### 3. Make yourself the first coach
1. Open the app and create an account with your email.
2. In Supabase **SQL Editor** run (with your email):
   ```sql
   update public.profiles set role = 'coach', status = 'approved' where email = 'you@example.com';
   ```
3. Reload the app. You now see Settings and every tab.

### 4. Add members and approve sign-ups
1. On the **Dues** tab, add each member with their fee and due date.
2. Members open the app link and tap **Create an account**.
3. You see a "waiting for approval" bar on top. Tap it, pick **Member** and choose which member record they are (or **Add as a new member**), then **Approve**.
4. To make another coach, approve them with the **Coach** role.
5. **Settings > Sign-ups and access** lets you revoke or reopen anyone.

## How access works
| | Coach | Member |
|---|---|---|
| Today, Workout, Board, Classes, News | full, can edit | view |
| Log workout scores | for any member | own, once only |
| PRs, class reservations | any member | own |
| Dues | everything | own, read-only |
| Approve sign-ups | yes | no |

These are enforced in the database (Row Level Security), not only in the page. Members cannot edit or delete a logged score, even by calling the API directly. A coach can delete an entry so a member can log again.

## Notes
- Member dues are copied to a member-readable record whenever a coach has the app open. If a member's dues look stale, open the app as a coach once.
- Realtime updates need the last step of `schema.sql` (included). The app also refreshes every 30 seconds as a fallback.
- Without valid keys in `config.js` the app opens in demo mode with sample data.
- Dues reminders are copy-and-send text messages for now. Automatic email or SMS needs a Supabase scheduled function, which can be added later.
