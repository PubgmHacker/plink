-- Sign in with Apple: stable subject from Apple identity token.
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "appleSub" TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS "User_appleSub_key" ON "User"("appleSub");
