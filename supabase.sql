-- =====================================================================
-- Tafelheld – database voor Supabase
-- Plak dit hele script in Supabase > SQL Editor > New query en klik "Run".
-- Je hoeft het maar één keer te doen.
-- =====================================================================

-- 1. Instellingen (welke tafels, beloning, geluid, verdiende stickers)
create table if not exists public.settings (
  user_id     uuid primary key default auth.uid() references auth.users on delete cascade,
  tables      int[]   not null default '{2,3,4,5,10}',
  reward_min  int     not null default 5,
  music       boolean not null default true,
  sfx         boolean not null default true,
  reward_ms   bigint  not null default 0,
  stickers    int[]   not null default '{}',
  updated_at  timestamptz not null default now()
);

-- 2. Oefenrondes (één rij per keer dat ze oefent)
create table if not exists public.sessions (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  started_at  timestamptz not null,
  ended_at    timestamptz,
  active_ms   int not null default 0,
  correct     int not null default 0,
  wrong       int not null default 0,
  device      text
);

-- 3. Antwoorden (één rij per som die ze beantwoordt)
create table if not exists public.answers (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  session_id  uuid references public.sessions(id) on delete cascade,
  a           int not null,          -- het keer-getal (bijv. 8 in 8 × 7)
  tafel       int not null,          -- de tafel (bijv. 7 in 8 × 7)
  given       int,                   -- wat ze invulde
  correct     boolean not null,
  ms          int not null,          -- bedenktijd in milliseconden
  created_at  timestamptz not null default now()
);

create index if not exists answers_user_fact on public.answers (user_id, tafel, a);
create index if not exists answers_session   on public.answers (session_id);
create index if not exists sessions_user_time on public.sessions (user_id, started_at);

-- 4. Beveiliging: iedereen ziet en wijzigt alleen zijn eigen gegevens
alter table public.settings enable row level security;
alter table public.sessions enable row level security;
alter table public.answers  enable row level security;

drop policy if exists "eigen instellingen" on public.settings;
create policy "eigen instellingen" on public.settings for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "eigen oefenrondes" on public.sessions;
create policy "eigen oefenrondes" on public.sessions for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "eigen antwoorden" on public.answers;
create policy "eigen antwoorden" on public.answers for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- 5. Samenvatting per som, voor de analyse en om lastige sommen vaker te vragen
create or replace view public.fact_stats with (security_invoker = true) as
select
  user_id,
  a,
  tafel,
  count(*)                                   as tries,
  count(*) filter (where correct)            as correct_count,
  sum(ms)                                    as total_ms,
  max(created_at)                            as last_at,
  (array_agg(given order by created_at desc) filter (where not correct))[1:6] as wrongs
from public.answers
group by user_id, a, tafel;

-- 6. Rechten voor ingelogde gebruikers (niet voor anonieme bezoekers)
grant select, insert, update, delete on public.settings, public.sessions, public.answers to authenticated;
grant select on public.fact_stats to authenticated;
revoke all on public.settings, public.sessions, public.answers, public.fact_stats from anon;
