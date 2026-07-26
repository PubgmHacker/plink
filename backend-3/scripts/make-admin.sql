-- Make koslakandrej@gmail.com an admin (FOUNDER role).
-- Run on Railway: dashboard → your PostgreSQL service → "Query" tab → paste → run.
--
-- FOUNDER has the same permissions as ADMIN but cannot be demoted by other admins.
-- If you want a regular ADMIN instead, change 'FOUNDER' to 'ADMIN'.

UPDATE "User"
SET role = 'FOUNDER',
    "updatedAt" = NOW()
WHERE email = 'koslakandrej@gmail.com';

-- Verify the change:
SELECT id, username, email, role, "isPremium" FROM "User" WHERE email = 'koslakandrej@gmail.com';
