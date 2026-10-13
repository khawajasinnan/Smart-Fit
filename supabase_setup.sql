-- ============================================================
-- SmartFit — Full Supabase Schema + RLS Setup
-- Run this in Supabase Dashboard > SQL Editor > New Query
-- ============================================================

-- STEP 1: Enable UUID extension (usually already enabled)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ============================================================
-- STEP 2: PROFILES TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id            UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         TEXT,
  username      TEXT        UNIQUE,
  full_name     TEXT        NOT NULL DEFAULT '',
  date_of_birth DATE,
  gender        TEXT,
  phone         TEXT,
  height        DECIMAL(5,2),
  weight        DECIMAL(5,2),
  height_cm     DECIMAL(5,2),
  weight_kg     DECIMAL(5,2),
  body_type     TEXT,
  avatar_url    TEXT,
  photo_url     TEXT,
  skin_tone     TEXT,
  chest_cm      DECIMAL(5,2),
  waist_cm      DECIMAL(5,2),
  hip_cm        DECIMAL(5,2),
  style_vibe    TEXT        DEFAULT 'Clean',
  style_preferences TEXT[]  DEFAULT '{}',
  preferred_colors  TEXT[]  DEFAULT '{}',
  budget_min    INTEGER,
  budget_max    INTEGER,
  occasions     TEXT[]      DEFAULT '{}',
  is_banned     BOOLEAN     DEFAULT FALSE,
  ban_reason    TEXT,
  banned_at     TIMESTAMPTZ,
  suspended_until TIMESTAMPTZ,
  suspension_reason TEXT,
  suspended_at  TIMESTAMPTZ,
  ethnicity     TEXT,
  profile_completed BOOLEAN   DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS email TEXT,
  ADD COLUMN IF NOT EXISTS username TEXT,
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS height_cm DECIMAL(5,2),
  ADD COLUMN IF NOT EXISTS weight_kg DECIMAL(5,2),
  ADD COLUMN IF NOT EXISTS photo_url TEXT,
  ADD COLUMN IF NOT EXISTS skin_tone TEXT,
  ADD COLUMN IF NOT EXISTS chest_cm DECIMAL(5,2),
  ADD COLUMN IF NOT EXISTS waist_cm DECIMAL(5,2),
  ADD COLUMN IF NOT EXISTS hip_cm DECIMAL(5,2),
  ADD COLUMN IF NOT EXISTS style_preferences TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS preferred_colors TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS budget_min INTEGER,
  ADD COLUMN IF NOT EXISTS budget_max INTEGER,
  ADD COLUMN IF NOT EXISTS occasions TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS is_banned BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS ban_reason TEXT,
  ADD COLUMN IF NOT EXISTS banned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS suspension_reason TEXT,
  ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ethnicity TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_unique
  ON public.profiles (LOWER(username))
  WHERE username IS NOT NULL AND username <> '';

CREATE OR REPLACE FUNCTION public.email_for_username(username_input TEXT)
RETURNS TEXT AS $$
  SELECT email
  FROM public.profiles
  WHERE LOWER(username) = LOWER(username_input)
  LIMIT 1;
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_smartfit_admin()
RETURNS BOOLEAN AS $$
  SELECT LOWER(COALESCE(auth.jwt() ->> 'email', '')) = 'admin@smartfit.pk';
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id OR public.is_smartfit_admin());

CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id OR public.is_smartfit_admin())
  WITH CHECK (auth.uid() = id OR public.is_smartfit_admin());

CREATE POLICY "Users can delete own profile"
  ON public.profiles FOR DELETE
  USING (auth.uid() = id);


-- ============================================================
-- STEP 3: CHAT SESSIONS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.chat_sessions (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title      TEXT        NOT NULL DEFAULT 'New Session',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.chat_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own chat sessions"
  ON public.chat_sessions FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);


-- ============================================================
-- STEP 4: CHAT MESSAGES TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID        NOT NULL REFERENCES public.chat_sessions(id) ON DELETE CASCADE,
  role       TEXT        NOT NULL CHECK (role IN ('user', 'assistant')),
  content    TEXT        NOT NULL,
  image_urls JSONB       NOT NULL DEFAULT '[]'::jsonb,
  metadata   JSONB,
  image_url  TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS image_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS metadata JSONB,
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own chat messages"
  ON public.chat_messages FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.chat_sessions cs
      WHERE cs.id = chat_messages.session_id
        AND cs.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.chat_sessions cs
      WHERE cs.id = chat_messages.session_id
        AND cs.user_id = auth.uid()
    )
  );

CREATE POLICY "Admin can view all chat sessions"
  ON public.chat_sessions FOR SELECT
  USING (public.is_smartfit_admin());

CREATE POLICY "Admin can view all chat messages"
  ON public.chat_messages FOR SELECT
  USING (public.is_smartfit_admin());

CREATE POLICY "Admin can update chat reviews"
  ON public.chat_messages FOR UPDATE
  USING (public.is_smartfit_admin())
  WITH CHECK (public.is_smartfit_admin());

CREATE OR REPLACE FUNCTION public.admin_mark_message_reviewed(message_id_input UUID)
RETURNS VOID AS $$
BEGIN
  IF NOT public.is_smartfit_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  UPDATE public.chat_messages
  SET
    reviewed_at = NOW(),
    metadata = jsonb_set(
      COALESCE(metadata, '{}'::jsonb),
      '{moderation,review_status}',
      '"reviewed"',
      true
    )
  WHERE id = message_id_input;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- STEP 5: ANALYSIS RESULTS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.analysis_results (
  id                    UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id               UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  overall_score         INTEGER     CHECK (overall_score BETWEEN 0 AND 100),
  color_harmony_score   INTEGER     CHECK (color_harmony_score BETWEEN 0 AND 100),
  fit_score             INTEGER     CHECK (fit_score BETWEEN 0 AND 100),
  style_score           INTEGER     CHECK (style_score BETWEEN 0 AND 100),
  suggestions           JSONB,
  image_url             TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.analysis_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own analysis results"
  ON public.analysis_results FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);


-- ============================================================
-- STEP 5B: PRODUCT CATALOG + ADMIN ROLES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.products (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  brand         TEXT        NOT NULL,
  title         TEXT        NOT NULL,
  category      TEXT,
  gender        TEXT,
  price_pkr     INTEGER,
  currency      TEXT        NOT NULL DEFAULT 'PKR',
  image_url     TEXT,
  product_url   TEXT        NOT NULL,
  sizes         TEXT[]      DEFAULT '{}',
  colors        TEXT[]      DEFAULT '{}',
  tags          TEXT[]      DEFAULT '{}',
  in_stock      BOOLEAN     DEFAULT TRUE,
  scraped_at    TIMESTAMPTZ DEFAULT NOW(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view products"
  ON public.products FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE TABLE IF NOT EXISTS public.admins (
  admin_id      UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  email         TEXT        NOT NULL UNIQUE,
  password_hash TEXT        NOT NULL,
  role          TEXT        NOT NULL DEFAULT 'admin',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- STEP 6: STORAGE BUCKETS
-- ============================================================

-- Avatars bucket (public read, authenticated write)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars', 'avatars', true,
  5242880, -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Chat images bucket (private)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-images', 'chat-images', false,
  10485760, -- 10 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;


-- ============================================================
-- STEP 7: STORAGE POLICIES
-- ============================================================

-- Avatars: anyone can read (public bucket)
CREATE POLICY "Public avatar read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

-- Avatars: only owner can upload/update their own avatar
CREATE POLICY "Users can upload own avatar"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can update own avatar"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can delete own avatar"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Chat images: only authenticated owner
CREATE POLICY "Users can manage own chat images"
  ON storage.objects FOR ALL
  USING (
    bucket_id = 'chat-images'
    AND auth.role() = 'authenticated'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'chat-images'
    AND auth.role() = 'authenticated'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );


-- ============================================================
-- STEP 8: TRIGGER — Auto-create profile on signup
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, date_of_birth, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    (NEW.raw_user_meta_data->>'date_of_birth')::date,
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- ============================================================
-- STEP 9: TRIGGER — Auto-update updated_at on profiles
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

DROP TRIGGER IF EXISTS chat_sessions_updated_at ON public.chat_sessions;
CREATE TRIGGER chat_sessions_updated_at
  BEFORE UPDATE ON public.chat_sessions
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE OR REPLACE FUNCTION public.touch_chat_session_from_message()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.chat_sessions
  SET updated_at = NOW()
  WHERE id = NEW.session_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_touch_session ON public.chat_messages;
CREATE TRIGGER chat_messages_touch_session
  AFTER INSERT ON public.chat_messages
  FOR EACH ROW EXECUTE PROCEDURE public.touch_chat_session_from_message();


-- ============================================================
-- STEP 10: SAVED PRODUCTS (Wardrobe) TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.saved_products (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  product_data  JSONB       NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS saved_products_user_id_idx
  ON public.saved_products (user_id);

ALTER TABLE public.saved_products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own saved products"
  ON public.saved_products FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own saved products"
  ON public.saved_products FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own saved products"
  ON public.saved_products FOR DELETE
  USING (auth.uid() = user_id);


-- ============================================================
-- Done! All tables, RLS policies, buckets, and triggers are set.
-- ============================================================
