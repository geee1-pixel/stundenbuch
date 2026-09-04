-- =====================================================================
-- Stundenbuch – Datenbankschema (Version 2)
-- Einmal im SQL-Editor von Supabase ausführen (Dashboard > SQL Editor).
-- Kann gefahrlos erneut ausgeführt werden, auch wenn Version 1 schon lief.
-- =====================================================================

-- ---------- Mitarbeiter ----------------------------------------------
create table if not exists mitarbeiter (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  rolle       text not null default 'werkstatt',   -- 'werkstatt' | 'fuehrung'
  pin         text,
  aktiv       boolean not null default true,
  angelegt_am timestamptz not null default now()
);

-- ---------- Tätigkeiten ----------------------------------------------
-- wertschoepfend : entsteht dabei etwas am Werkstück?
-- verrechenbar   : kann es dem Kunden in Rechnung gestellt werden?
-- auftrag_noetig : muss eine Auftragsnummer angegeben werden?
create table if not exists taetigkeiten (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  wertschoepfend boolean not null default true,
  verrechenbar   boolean not null default true,
  auftrag_noetig boolean not null default true,
  sortierung     int not null default 100,
  aktiv          boolean not null default true
);

-- ---------- Aufträge --------------------------------------------------
create table if not exists auftraege (
  id                  uuid primary key default gen_random_uuid(),
  nummer              text not null,
  kunde               text,
  bezeichnung         text,
  art                 text,
  kalkulierte_stunden numeric(8,2) not null default 0,
  angebotssumme       numeric(12,2),
  materialkosten      numeric(12,2),
  status              text not null default 'offen',   -- 'offen' | 'abgeschlossen'
  abschluss_notiz     text,
  abgeschlossen_am    date,
  angelegt_am         timestamptz not null default now()
);

-- ---------- Zeitbuchungen --------------------------------------------
create table if not exists zeiten (
  id             uuid primary key default gen_random_uuid(),
  client_id      text unique,
  auftrag_id     uuid references auftraege(id) on delete set null,
  mitarbeiter_id uuid references mitarbeiter(id) on delete set null,
  taetigkeit_id  uuid references taetigkeiten(id) on delete set null,
  datum          date not null,
  stunden        numeric(6,2) not null check (stunden > 0 and stunden <= 24),
  notiz          text,
  nachtrag       boolean not null default false,
  foto           text,
  erfasst_am     timestamptz not null default now()
);

-- ---------- Anwesenheit ----------------------------------------------
-- Wie lange war jemand an diesem Tag da? Grundlage für den Abgleich
-- "anwesend gegen zugeordnet". Ersetzt keine gesetzliche Zeiterfassung.
create table if not exists anwesenheit (
  id             uuid primary key default gen_random_uuid(),
  mitarbeiter_id uuid not null references mitarbeiter(id) on delete cascade,
  datum          date not null,
  stunden        numeric(5,2) not null check (stunden >= 0 and stunden <= 24),
  unique (mitarbeiter_id, datum)
);

-- ---------- Einstellungen --------------------------------------------
create table if not exists einstellungen (
  schluessel text primary key,
  wert       text
);

-- ---------- Nachrüsten für bestehende Version-1-Datenbanken -----------
alter table zeiten    add column if not exists nachtrag boolean not null default false;
alter table zeiten    add column if not exists foto text;
alter table auftraege add column if not exists abschluss_notiz text;
alter table auftraege add column if not exists abgeschlossen_am date;

create index if not exists zeiten_auftrag_idx     on zeiten (auftrag_id);
create index if not exists zeiten_mitarbeiter_idx on zeiten (mitarbeiter_id, datum desc);
create index if not exists zeiten_datum_idx       on zeiten (datum desc);
create index if not exists anwesenheit_idx        on anwesenheit (datum desc);

-- ---------- Startdaten -----------------------------------------------
insert into taetigkeiten (name, wertschoepfend, verrechenbar, auftrag_noetig, sortierung)
select * from (values
  ('Fertigung Werkstatt',           true,  true,  true,  10),
  ('Montage vor Ort',               true,  true,  true,  20),
  ('Aufmaß',                        true,  true,  true,  30),
  ('Konstruktion / CNC',            true,  true,  true,  40),
  ('Angebot / Büro',                false, true,  false, 45),
  ('Fahrt',                         false, true,  true,  50),
  ('Beladen / Rüsten',              false, true,  true,  60),
  ('Suchen von Werkzeug/Material',  false, false, true,  70),
  ('Wartezeit auf Vorgewerk',       false, false, true,  80),
  ('Maschinenstörung',              false, false, false, 85),
  ('Ausfall (Wetter, Absage)',      false, false, false, 88),
  ('Nacharbeit / Reklamation',      false, false, true,  90),
  ('Werkstatt intern',              false, false, false, 100)
) as neu(name, wertschoepfend, verrechenbar, auftrag_noetig, sortierung)
where not exists (select 1 from taetigkeiten t where t.name = neu.name);

insert into einstellungen (schluessel, wert)
select 'rueckmeldung', '0'
where not exists (select 1 from einstellungen where schluessel = 'rueckmeldung');

-- ---------- Zugriff ---------------------------------------------------
-- Achtung: Jeder, der Adresse und anon-Key kennt, kann lesen und schreiben.
-- Für einen internen Betrieb mit vier Personen vertretbar, solange der Link
-- nicht öffentlich wird.
alter table mitarbeiter   enable row level security;
alter table taetigkeiten  enable row level security;
alter table auftraege     enable row level security;
alter table zeiten        enable row level security;
alter table anwesenheit   enable row level security;
alter table einstellungen enable row level security;

drop policy if exists "intern_mitarbeiter"   on mitarbeiter;
drop policy if exists "intern_taetigkeiten"  on taetigkeiten;
drop policy if exists "intern_auftraege"     on auftraege;
drop policy if exists "intern_zeiten"        on zeiten;
drop policy if exists "intern_anwesenheit"   on anwesenheit;
drop policy if exists "intern_einstellungen" on einstellungen;

create policy "intern_mitarbeiter"   on mitarbeiter   for all using (true) with check (true);
create policy "intern_taetigkeiten"  on taetigkeiten  for all using (true) with check (true);
create policy "intern_auftraege"     on auftraege     for all using (true) with check (true);
create policy "intern_zeiten"        on zeiten        for all using (true) with check (true);
create policy "intern_anwesenheit"   on anwesenheit   for all using (true) with check (true);
create policy "intern_einstellungen" on einstellungen for all using (true) with check (true);

-- ---------- Erste Person anlegen -------------------------------------
-- Namen und PIN anpassen, dann ausführen.
insert into mitarbeiter (name, rolle, pin)
select 'Chef', 'fuehrung', '1234'
where not exists (select 1 from mitarbeiter);
