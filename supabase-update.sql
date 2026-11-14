-- =====================================================================
-- Tafelheld – database-update (bevat ALLE updates tot nu toe)
-- Plak dit in Supabase > SQL Editor > New query en klik "Run".
-- Je mag dit gerust vaker uitvoeren; wat er al is, blijft gewoon staan.
-- =====================================================================

-- Langste reeks
alter table public.settings add column if not exists best_streak    int not null default 0;
alter table public.settings add column if not exists best_streak_at timestamptz;
alter table public.sessions add column if not exists best_streak    int not null default 0;

-- Toetsinstellingen
alter table public.settings add column if not exists test_n   int not null default 20;
alter table public.settings add column if not exists test_sec int not null default 3;

-- Denktijd bij oefenen: tijd tot het eerste cijfer (milliseconden)
alter table public.answers add column if not exists first_ms int;

-- Toetsen (één rij per toets)
create table if not exists public.tests (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  started_at  timestamptz not null,
  ended_at    timestamptz,
  mode        text not null check (mode in ('zelf','overhoor')),
  planned     int not null default 0,
  total       int not null default 0,
  vlot        int not null default 0,
  laat        int not null default 0,
  fout        int not null default 0,
  seconds     int not null default 3,
  device      text
);

-- Toetsantwoorden (één rij per som in een toets)
create table if not exists public.test_answers (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  test_id     uuid references public.tests(id) on delete cascade,
  a           int not null,
  tafel       int not null,
  mode        text,
  given       int,                 -- leeg bij overhoren
  result      text not null check (result in ('vlot','laat','fout')),
  recall_ms   int,                 -- tijd tot "Ik weet het!" (of tot de ouder tikte)
  first_ms    int,                 -- daarna: tijd tot het eerste cijfer
  created_at  timestamptz not null default now()
);
create index if not exists tests_user_time on public.tests (user_id, started_at);
create index if not exists test_answers_user_fact on public.test_answers (user_id, tafel, a);

alter table public.tests        enable row level security;
alter table public.test_answers enable row level security;

drop policy if exists "eigen toetsen" on public.tests;
create policy "eigen toetsen" on public.tests for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "eigen toetsantwoorden" on public.test_answers;
create policy "eigen toetsantwoorden" on public.test_answers for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

grant select, insert, update, delete on public.tests, public.test_answers to authenticated;
revoke all on public.tests, public.test_answers from anon;

-- Samenvatting per som, nu ook met denktijd en "vlot" (≤ 3 seconden)
create or replace view public.fact_stats with (security_invoker = true) as
select
  user_id,
  a,
  tafel,
  count(*)                                   as tries,
  count(*) filter (where correct)            as correct_count,
  sum(ms)                                    as total_ms,
  max(created_at)                            as last_at,
  (array_agg(given order by created_at desc) filter (where not correct))[1:6] as wrongs,
  count(first_ms)                                         as timed_all,
  count(first_ms) filter (where correct)                  as timed_correct,
  sum(first_ms)   filter (where correct)                  as first_ms_sum,
  count(*)        filter (where correct and first_ms <= 3000) as quick_count
from public.answers
group by user_id, a, tafel;

grant select on public.fact_stats to authenticated;

-- Toetstijd: totale tijd en tijd per som
alter table public.tests        add column if not exists duration_ms int;  -- hele toets, inclusief pauzes
alter table public.tests        add column if not exists net_ms      int;  -- opgetelde tijd per som
alter table public.test_answers add column if not exists ms          int;  -- tijd van tonen tot antwoord/beoordeling

-- Thema's: gekozen thema en verzamelde pepernoten / kerstballen / oliebollen
alter table public.settings add column if not exists theme   text  not null default 'auto';
alter table public.settings add column if not exists collect jsonb not null default '{}'::jsonb;

-- Tafels die al gehaald zijn op school (komen minder vaak terug)
alter table public.settings add column if not exists passed int[] not null default '{}';

-- Snake als beloning: record, vorige score en instelling
alter table public.settings add column if not exists snake jsonb not null default '{}'::jsonb;
