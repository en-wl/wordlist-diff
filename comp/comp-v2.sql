begin;

set search_path = working,util,public;

create temp table new_words (word text primary key);
\copy new_words from 'en_US-60.new'

create temp table ok_added (word text primary key);
\copy ok_added from 'added-words'

--

drop table if exists comm;
create table comm (
  old text unique,
  new text unique,
  ok boolean,
  note text
);
insert into comm (old, new) select old.word, new.word from orig_words as old full join new_words as new on old.word = new.word
  where old.word is null or new.word is null;

--

update comm set ok = true, note = 'possessive'
  where old like '%''s';
  
update comm set ok = true, note = 'possessive'
  where new like '%''s';

update comm set ok = true, note = 'archaic'
 where ok is null and old in (
   select old from comm join v2.scowl_ on old=word join v2.variant_levels using (variant_level) where size <= 60 and spelling in ('_', 'A') group by old having bool_and(entry_rank = '@' or variant_symbol = '@')
 );

update comm set ok = true, note = 'uncommon derived aj/av'
  where ok is null and old in (
    select old from comm join v2.entries on old=word group by old having bool_and(coalesce(entry_rank, '') != '' and base_pos in ('a', 'aj', 'av'))
  );

update comm set ok = true, note = 'uncommon form'
 where ok is null and old in (
   select old from comm join v2.entries on old=word group by old having single(group_rank) != ''
 );

update comm set ok = false, note = 'closed form of compound word'
 from v2.entries as a, v2.lemma_variant_info as av, v2.lemmas as b, v2.lemma_variant_info as bv, v2.group_comments c 
 where ok is null
   and comm.old = a.word and a.lemma_id = av.lemma_id
   and a.group_id = b.group_id and b.lemma_id = bv.lemma_id
   and av.variant_level <= 4 and b.lemma ~ '[ -]' and a.lemma = regexp_replace(b.lemma, '[ -]', '', 'g')
   and b.group_id = c.group_id and c.comment ~ 'best guess';

update comm set note = 'closed form of compound word marked as variant'
 from v2.entries as a, v2.lemma_variant_info as av, v2.lemmas as b, v2.lemma_variant_info as bv
 where note is null
   and comm.old = a.word and a.lemma_id = av.lemma_id
   and a.group_id = b.group_id and b.lemma_id = bv.lemma_id
   and b.lemma ~ '[ -]' and a.lemma = regexp_replace(b.lemma, '[ -]', '', 'g');

update comm set note = 'common variant'
 where note is null and old in (
   select old from comm join v2.scowl_ on old=word where size <= 60 and spelling in ('_', 'A') group by old having bool_and(variant_level = 4 or variant_level >= 6)
 );


update comm set ok = true, note = 'variant'
 where ok is null and old in (
   select old from comm join v2.scowl_ on old=word where size <= 60 and spelling in ('_', 'A') group by old having bool_and(variant_level >= 6)
 );

update comm set note = 'variant'
 where note is null and old in (
   select old from comm join v2.scowl_ on old=word where size <= 60 and spelling in ('_', 'A') group by old having bool_and(variant_level >= 4)
 );


update comm set ok = true, note = 'other'
where ok is null and old in (table ok_missing);

update comm set ok = true, note = 'improper derived'
where ok is null and old in (table improper_derived);

update comm set note = 'in 2of12id', ok = true
 where ok is null
   and new in (select word from in_2of12id where variant_level = '');
  
update comm set note = 'in 2of12id, but marked as a variant' 
 where ok is null and note is null
   and new in (select word from in_2of12id);

update comm set ok = true, note = 'added'
 from v2.entries
 where new=word
  and ok is null
  and (word in (table ok_added));

update comm set ok = true, note = 'closed form of compound word'
 from v2.entries as a, v2.lemma_variant_info as av, v2.lemmas as b, v2.lemma_variant_info as bv
 where ok is null
   and comm.new = a.word and a.lemma_id = av.lemma_id
   and a.group_id = b.group_id and b.lemma_id = bv.lemma_id
   and av.variant_level <= 1 and b.lemma ~ '[ -]' and a.lemma = regexp_replace(b.lemma, '[ -]', '', 'g');

update comm set ok = true, note = 'other'
 from v2.entries
 where new=word
  and ok is null
  and (word in (table ok_new) or lemma in (table ok_new));

update comm set ok = false, note = 'other'
 from v2.entries
 where new=word
  and ok is null
  and lemma in (table not_ok_new);

update comm set ok = true, note = 'all-upper lemma'
where new in (select word from comm join v2.entries on new=word where old is null and ok is null  and lemma ~ '^[A-Z]+$');

update comm set note = 'upper plural'
 from v2.entries
where new=word
  and new ~'[A-Z]'
  and ok is null and note is null
  and pos = 'ns'
  and lemma not in (select new from comm where new is not null);

update comm set note = 'upper'
where ok is null and note is null and (new ~'[A-Z]' or old ~'[A-Z]');

commit;
