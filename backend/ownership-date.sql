-- Apply once after schema.sql. Month/year placeholders preserve their original meaning in notes.
update public.home_equipment set
 notes=concat_ws(E'\n',nullif(notes,''),case
  when ownership_date ~ '^\d{4}-\d{2}$' then 'Ownership date was originally recorded as '||ownership_date||'; day 1 was used when converting it to a full date.'
  else 'Ownership date was originally recorded as '||ownership_date||'; January 1 was used when converting it to a full date.' end),
 revision=revision+1,updated_at=now()
where ownership_date ~ '^\d{4}(-\d{2})?$';
alter table public.home_equipment alter column ownership_date type date using
 case when nullif(trim(ownership_date),'') is null then null
 when ownership_date ~ '^\d{4}$' then (ownership_date||'-01-01')::date
 when ownership_date ~ '^\d{4}-\d{2}$' then (ownership_date||'-01')::date
 else ownership_date::date end;
create or replace function home_private.save_equipment(p_id text,p_revision integer,p_values jsonb) returns public.home_equipment language plpgsql security definer set search_path='' as $$declare result public.home_equipment;expiry date;owned date;raw_owned text;begin
 perform home_private.check_access();
 if length(trim(coalesce(p_values->>'name','')))=0 then raise exception 'Equipment name is required.';end if;
 raw_owned:=nullif(p_values->>'ownership_date','');
 if raw_owned is not null then
  if raw_owned !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Choose a full purchase/ownership date. Use the first of the month if the day is unknown.';end if;
  begin owned:=raw_owned::date;exception when invalid_datetime_format or datetime_field_overflow then raise exception 'Choose a valid purchase/ownership date.';end;
  if owned>(now() at time zone 'America/New_York')::date then raise exception 'Purchase/ownership date cannot be in the future.';end if;
 end if;
 expiry:=nullif(p_values->>'warranty_expiry_date','')::date;
 if nullif(p_values->>'manual_url','') is not null and p_values->>'manual_url' !~ '^https?://' then raise exception 'Use a full HTTP or HTTPS manual link.';end if;
 update public.home_equipment set name=trim(p_values->>'name'),manufacturer=nullif(p_values->>'manufacturer',''),category=nullif(p_values->>'category',''),model=nullif(p_values->>'model',''),serial_number=nullif(p_values->>'serial_number',''),ownership_date=owned,warranty_status=coalesce(nullif(p_values->>'warranty_status',''),'unknown'),warranty_expiry_date=expiry,warranty_notes=nullif(p_values->>'warranty_notes',''),manual_url=nullif(p_values->>'manual_url',''),notes=nullif(p_values->>'notes',''),revision=revision+1,updated_at=now() where id=p_id and revision=p_revision returning * into result;
 if not found then raise exception 'This record changed elsewhere. Reopen the latest version before saving.' using errcode='40001';end if;
 return result;
end;$$;
notify pgrst,'reload schema';
