-- STUFF #62 — public contact form. Stores submissions for the
-- operator to review at /admin/support. The repo is private so an
-- "open an issue" link doesn't work; email-in-the-footer is a
-- spam magnet. This table is the third path: form-in, admin-queue
-- out, manual reply to the optional reply_to outside the system.
--
-- user_id is nullable: anonymous (signed-out) submissions are
-- accepted. When the submitter is signed in we link them so the
-- admin queue can show their username for context.
--
-- reply_to is the user-supplied contact handle (email, mastodon,
-- whatever). Optional — if blank, the operator just acks internally.
--
-- status is a small enum-as-text: 'new' (just arrived),
-- 'reviewed' (admin saw it but no action needed), 'responded'
-- (admin replied out-of-band). admin_note is private to the
-- operator.
CREATE TABLE support_messages (
  id          BIGSERIAL PRIMARY KEY,
  user_id     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  subject     VARCHAR(200),
  body        TEXT NOT NULL,
  reply_to    VARCHAR(200),
  status      VARCHAR(20) NOT NULL DEFAULT 'new',
  admin_note  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX support_messages_status_created_idx
  ON support_messages (status, created_at DESC);
