begin;

drop schema if exists working cascade;
create schema working;

set search_path = working;

create table orig_words (word text primary key);
\copy orig_words from 'comp/en_US-60.orig'

-- create temp table in_2of12id as
-- select word,variant_level from alan.a_id_line l join alan.a_id_entry e using (lid) where not (l.uncommon or l.archaic or l.infrequent or e.uncommon or e.archaic or e.inapplicable or e.infrequent);
-- \copy (select * from in_2of12id order by word, variant_level) to '/tmp/in_2of12id.tab'

create temp table _in_2of12id (word text not null, variant_level text not null);
\copy _in_2of12id from 'comp/in_2of12id.tab'
create table in_2of12id (word text primary key, variant_level text not null);
insert into in_2of12id
select word,min(variant_level) from _in_2of12id group by word;
drop table _in_2of12id;

create table ok_missing (word text primary key);
\copy ok_missing from 'comp/ok-missing'

create table improper_derived (word text primary key);
\copy improper_derived from 'comp/improper-derived'

create table ok_new (word text primary key);
\copy ok_new from 'comp/ok-new'

create table not_ok_new (word text primary key);
\copy not_ok_new from 'comp/not-ok-new'

analyze;

commit;
