-- SmartFit — Add ethnicity column to profiles
-- Run this in Supabase Dashboard > SQL Editor > New Query
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS ethnicity TEXT;
