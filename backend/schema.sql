-- Generic schema only. Never commit household records, document bytes or member emails.
create schema home_private;
revoke all on schema home_private from public,anon;
grant usage on schema home_private to authenticated;
create table home_private.members(email text primary key check(email=lower(email)),active boolean not null default true);
alter table home_private.members enable row level security;
revoke all on home_private.members from public,anon,authenticated;
create function home_private.allowed() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users u join home_private.members m on m.email=lower(u.email) where u.id=auth.uid() and u.email_confirmed_at is not null and m.active);
$$;
revoke all on function home_private.allowed() from public,anon;
grant execute on function home_private.allowed() to authenticated;
create table public.home_equipment(
 id text primary key,name text not null check(length(trim(name))>0),manufacturer text,category text,model text,serial_number text,ownership_date text,
 warranty_status text not null default 'unknown' check(warranty_status in('unknown','unresolved','confirmed','expired')),
 warranty_expiry_date date,warranty_notes text,manual_url text,notes text,
 evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(evidence)='object'),revision integer not null default 1,updated_at timestamptz not null default now()
);
create table public.home_tasks(
 id text primary key,title text not null check(length(trim(title))>0),timing text,notes text,next_due_date date,last_completed_date date,
 recurrence_unit text check(recurrence_unit in('months','years')),recurrence_interval integer check(recurrence_interval between 1 and 120),recurrence_month integer check(recurrence_month between 1 and 12),calendar_months integer[] not null default '{}',schedule_status text,
 revision integer not null default 1,updated_at timestamptz not null default now()
);
create table public.home_task_equipment(task_id text references public.home_tasks(id),equipment_id text references public.home_equipment(id),primary key(task_id,equipment_id));
create table public.home_history(
 id text primary key,kind text not null check(kind in('maintenance','modification')),date text not null,description text not null check(length(trim(description))>0),provider text,cost text,receipt text,task_id text references public.home_tasks(id),evidence jsonb not null default '{}',created_at timestamptz not null default now()
);
create table public.home_history_equipment(history_id text references public.home_history(id),equipment_id text references public.home_equipment(id),primary key(history_id,equipment_id));
create table public.home_attention(
 id text primary key,equipment_id text references public.home_equipment(id),task_id text references public.home_tasks(id),question text not null,status text not null default 'open' check(status in('open','in_progress','resolved','not_applicable')),resolution text not null default '',revision integer not null default 1,updated_at timestamptz not null default now()
);
create table public.home_documents(id text primary key,title text not null,kind text not null default 'other',url text,filename text,content_type text,check(url is not null or filename is not null));
create table public.home_document_equipment(document_id text references public.home_documents(id),equipment_id text references public.home_equipment(id),primary key(document_id,equipment_id));
create table home_private.document_files(document_id text primary key references public.home_documents(id),content bytea not null check(octet_length(content)<=1048576));
alter table home_private.document_files enable row level security;
revoke all on home_private.document_files from public,anon,authenticated;
-- Preserved evidence and historical source material are not exposed in everyday navigation.
create table home_private.migration_evidence(id text primary key,details jsonb not null);
alter table home_private.migration_evidence enable row level security;
revoke all on home_private.migration_evidence from public,anon,authenticated;
do $$declare tab text;begin
 foreach tab in array array['home_equipment','home_tasks','home_task_equipment','home_history','home_history_equipment','home_attention','home_documents','home_document_equipment'] loop
 execute format('alter table public.%I enable row level security',tab);
 execute format('revoke all on public.%I from public,anon,authenticated',tab);
 execute format('grant select on public.%I to authenticated',tab);
 execute format('create policy home_member_read on public.%I for select to authenticated using ((select home_private.allowed()))',tab);
 end loop;
end;$$;
create function home_private.check_access() returns void language plpgsql stable security definer set search_path='' as $$begin
 if not home_private.allowed() then raise exception 'This account does not have home maintenance access.' using errcode='42501';end if;
end;$$;
create function home_private.valid_partial(value text) returns boolean language plpgsql immutable set search_path='' as $$begin
 if value ~ '^\d{4}$' then return value::integer between 1801 and 9999;
 elsif value ~ '^\d{4}-\d{2}$' then return to_char((value||'-01')::date,'YYYY-MM')=value;
 elsif value ~ '^\d{4}-\d{2}-\d{2}$' then return to_char(value::date,'YYYY-MM-DD')=value;
 else return false;end if;
 exception when others then return false;end;$$;
create function home_private.require_partial(value text) returns void language plpgsql set search_path='' as $$begin
 if value is not null and value<>'' and (not home_private.valid_partial(value) or value>to_char(current_date,'YYYY-MM-DD')) then raise exception 'Enter a valid past or current date (year, month or day).';end if;
end;$$;
create function home_private.save_equipment(p_id text,p_revision integer,p_values jsonb) returns public.home_equipment language plpgsql security definer set search_path='' as $$declare result public.home_equipment;expiry date;begin
 perform home_private.check_access();
 if length(trim(coalesce(p_values->>'name','')))=0 then raise exception 'Equipment name is required.';end if;
 perform home_private.require_partial(nullif(p_values->>'ownership_date',''));
 expiry:=nullif(p_values->>'warranty_expiry_date','')::date;
 if nullif(p_values->>'manual_url','') is not null and p_values->>'manual_url' !~ '^https?://' then raise exception 'Use a full HTTP or HTTPS manual link.';end if;
 update public.home_equipment set name=trim(p_values->>'name'),manufacturer=nullif(p_values->>'manufacturer',''),category=nullif(p_values->>'category',''),model=nullif(p_values->>'model',''),serial_number=nullif(p_values->>'serial_number',''),ownership_date=nullif(p_values->>'ownership_date',''),warranty_status=coalesce(nullif(p_values->>'warranty_status',''),'unknown'),warranty_expiry_date=expiry,warranty_notes=nullif(p_values->>'warranty_notes',''),manual_url=nullif(p_values->>'manual_url',''),notes=nullif(p_values->>'notes',''),revision=revision+1,updated_at=now() where id=p_id and revision=p_revision returning * into result;
 if not found then raise exception 'This record changed elsewhere. Reopen the latest version before saving.' using errcode='40001';end if;
 return result;
end;$$;
create function home_private.save_attention(p_id text,p_revision integer,p_status text,p_resolution text) returns public.home_attention language plpgsql security definer set search_path='' as $$declare result public.home_attention;begin
 perform home_private.check_access();
 if p_status in('resolved','not_applicable') and length(trim(coalesce(p_resolution,'')))=0 then raise exception 'Add a short resolution note.';end if;
 update public.home_attention set status=p_status,resolution=coalesce(p_resolution,''),revision=revision+1,updated_at=now() where id=p_id and revision=p_revision returning * into result;
 if not found then raise exception 'This follow-up changed elsewhere. Reopen the latest version.' using errcode='40001';end if;return result;
end;$$;
create function home_private.save_task(p_id text,p_revision integer,p_values jsonb) returns public.home_tasks language plpgsql security definer set search_path='' as $$declare result public.home_tasks;begin
 perform home_private.check_access();
 if length(trim(coalesce(p_values->>'title','')))=0 then raise exception 'Task name is required.';end if;
 update public.home_tasks set title=trim(p_values->>'title'),timing=p_values->>'timing',notes=p_values->>'notes',next_due_date=nullif(p_values->>'next_due_date','')::date,recurrence_unit=nullif(p_values->>'recurrence_unit',''),recurrence_interval=nullif(p_values->>'recurrence_interval','')::integer,recurrence_month=nullif(p_values->>'recurrence_month','')::integer,revision=revision+1,updated_at=now() where id=p_id and revision=p_revision returning * into result;
 if not found then raise exception 'This task changed elsewhere. Reopen the latest version.' using errcode='40001';end if;return result;
end;$$;
create function home_private.log_work(p_operation_id uuid,p_kind text,p_date text,p_description text,p_equipment_ids text[],p_provider text default null,p_cost text default null,p_receipt text default null,p_task_id text default null,p_task_revision integer default null,p_next_due_date date default null) returns text language plpgsql security definer set search_path='' as $$declare result text:=p_operation_id::text; existing public.home_history;task public.home_tasks;chosen text;begin
 perform home_private.check_access();
 -- Stable operation ID makes retrying after an uncertain network result safe.
 perform pg_advisory_xact_lock(hashtextextended(result,0));
 select * into existing from public.home_history where id=result;
 if found then
 if existing.kind<>p_kind or existing.date<>p_date or existing.description<>p_description or existing.task_id is distinct from p_task_id then raise exception 'This work identifier was already used. Reopen the form.';end if;return result;end if;
 if p_kind not in('maintenance','modification') or length(trim(coalesce(p_description,'')))=0 then raise exception 'Work type and description are required.';end if;
 perform home_private.require_partial(p_date);
 if p_date is null or p_date='' or (p_kind='maintenance' and p_date !~ '^\d{4}-\d{2}-\d{2}$') then raise exception 'Completed maintenance requires an exact completion date.';end if;
 if coalesce(cardinality(p_equipment_ids),0)=0 and p_task_id is null then raise exception 'Choose equipment or a household task.';end if;
 if exists(select 1 from unnest(p_equipment_ids) i where not exists(select 1 from public.home_equipment e where e.id=i)) then raise exception 'Unknown equipment.';end if;
 if p_task_id is not null then
 select * into task from public.home_tasks where id=p_task_id for update;
 if not found or task.revision<>p_task_revision then raise exception 'This task changed elsewhere. Reopen the latest version.' using errcode='40001';end if;
 if p_kind<>'maintenance' then raise exception 'Task completion must be maintenance.';end if;
 end if;
 insert into public.home_history(id,kind,date,description,provider,cost,receipt,task_id) values(result,p_kind,p_date,trim(p_description),nullif(p_provider,''),nullif(p_cost,''),nullif(p_receipt,''),p_task_id);
 if p_task_id is not null then
 insert into public.home_history_equipment select result,equipment_id from public.home_task_equipment where task_id=p_task_id;
 update public.home_tasks set last_completed_date=greatest(last_completed_date,p_date::date),next_due_date=p_next_due_date,revision=revision+1,updated_at=now() where id=p_task_id;
 else
 insert into public.home_history_equipment select distinct result,unnest(p_equipment_ids);
 end if;return result;
end;$$;
create function home_private.document(p_id text) returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 perform home_private.check_access();
 select jsonb_build_object('filename',d.filename,'content_type',d.content_type,'base64',encode(f.content,'base64')) into result from public.home_documents d join home_private.document_files f on f.document_id=d.id where d.id=p_id;
 if result is null then raise exception 'Saved document not found.';end if;return result;
end;$$;
create function public.home_save_equipment(p_id text,p_revision integer,p_values jsonb) returns public.home_equipment language sql security invoker set search_path='' as $$select home_private.save_equipment(p_id,p_revision,p_values);$$;
create function public.home_save_attention(p_id text,p_revision integer,p_status text,p_resolution text) returns public.home_attention language sql security invoker set search_path='' as $$select home_private.save_attention(p_id,p_revision,p_status,p_resolution);$$;
create function public.home_save_task(p_id text,p_revision integer,p_values jsonb) returns public.home_tasks language sql security invoker set search_path='' as $$select home_private.save_task(p_id,p_revision,p_values);$$;
create function public.home_log_work(p_operation_id uuid,p_kind text,p_date text,p_description text,p_equipment_ids text[],p_provider text default null,p_cost text default null,p_receipt text default null,p_task_id text default null,p_task_revision integer default null,p_next_due_date date default null) returns text language sql security invoker set search_path='' as $$select home_private.log_work(p_operation_id,p_kind,p_date,p_description,p_equipment_ids,p_provider,p_cost,p_receipt,p_task_id,p_task_revision,p_next_due_date);$$;
create function public.home_document(p_id text) returns jsonb language sql security invoker set search_path='' as $$select home_private.document(p_id);$$;
create function public.home_access() returns boolean language sql stable security invoker set search_path='' as $$select home_private.allowed();$$;
-- Revoke implicit PostgreSQL PUBLIC function execution, including helper functions.
revoke all on all functions in schema home_private from public,anon,authenticated;
grant execute on function home_private.allowed(),home_private.save_equipment(text,integer,jsonb),home_private.save_attention(text,integer,text,text),home_private.save_task(text,integer,jsonb),home_private.log_work(uuid,text,text,text,text[],text,text,text,text,integer,date),home_private.document(text) to authenticated;
revoke all on function public.home_save_equipment(text,integer,jsonb),public.home_save_attention(text,integer,text,text),public.home_save_task(text,integer,jsonb),public.home_log_work(uuid,text,text,text,text[],text,text,text,text,integer,date),public.home_document(text),public.home_access() from public,anon,authenticated;
grant execute on function public.home_save_equipment(text,integer,jsonb),public.home_save_attention(text,integer,text,text),public.home_save_task(text,integer,jsonb),public.home_log_work(uuid,text,text,text,text[],text,text,text,text,integer,date),public.home_document(text),public.home_access() to authenticated;
notify pgrst,'reload schema';
