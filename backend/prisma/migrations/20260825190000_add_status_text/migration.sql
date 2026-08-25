-- Discord-style custom status on the profile card. Nullable text, no default.
ALTER TABLE "User" ADD COLUMN "statusText" TEXT;
