-- Add task creation without changing existing tasks or equipment.
create function home_private.create_task(p_operation_id uuid,p_equipment_id text,p_values jsonb) returns public.home_tasks
language plpgsql security definer set search_path='' as $$
declare result public.home_tasks;task_id text;equipment text:=nullif(trim(p_equipment_id),'');task_title text:=trim(p_values->>'title');task_notes text:=nullif(trim(p_values->>'notes'),'');unit text:=nullif(p_values->>'recurrence_unit','');frequency integer;due date;raw_due text:=nullif(p_values->>'next_due_date','');timing text;linked text[];
begin
 perform home_private.check_access();
 if p_operation_id is null then raise exception 'Reopen the form before saving.';end if;
 if coalesce(length(task_title),0)=0 or length(task_title)>500 then raise exception 'Enter a task name (up to 500 characters).';end if;
 if coalesce(length(task_notes),0)>5000 then raise exception 'Keep notes under 5,000 characters.';end if;
 if equipment is not null and not exists(select 1 from public.home_equipment where id=equipment) then raise exception 'Choose an existing equipment item.';end if;
 if unit is not null then
  if unit not in('months','years') then raise exception 'Choose months, years or one time / as needed.';end if;
  if coalesce(p_values->>'recurrence_interval','') !~ '^\d{1,3}$' then raise exception 'Enter a repeat interval between 1 and 120.';end if;
  frequency:=(p_values->>'recurrence_interval')::integer;
  if frequency not between 1 and 120 then raise exception 'Enter a repeat interval between 1 and 120.';end if;
 end if;
 if raw_due is not null then
  if raw_due !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Choose a full next due date or leave it blank.';end if;
  begin due:=raw_due::date;exception when invalid_datetime_format or datetime_field_overflow then raise exception 'Choose a valid next due date.';end;
 end if;
 timing:=case when unit is null then 'One time / as needed' when frequency=1 then 'Every '||case unit when 'months' then 'month' else 'year' end else 'Every '||frequency::text||' '||unit end;
 task_id:='task-'||p_operation_id::text;
 perform pg_advisory_xact_lock(hashtextextended(task_id,0));
 select * into result from public.home_tasks where id=task_id;
 if found then
  select coalesce(array_agg(equipment_id order by equipment_id),'{}'::text[]) into linked from public.home_task_equipment where home_task_equipment.task_id=result.id;
  if result.title is distinct from task_title or result.notes is distinct from task_notes or result.next_due_date is distinct from due or result.recurrence_unit is distinct from unit or result.recurrence_interval is distinct from frequency or linked is distinct from (case when equipment is null then '{}'::text[] else array[equipment] end) then
   raise exception 'This task was already saved with different details. Refresh Schedule to review it.';
  end if;
  return result;
 end if;
 insert into public.home_tasks(id,title,timing,notes,next_due_date,recurrence_unit,recurrence_interval,schedule_status)
 values(task_id,task_title,timing,task_notes,due,unit,frequency,'confirmed') returning * into result;
 if equipment is not null then insert into public.home_task_equipment(task_id,equipment_id) values(result.id,equipment);end if;
 return result;
end;$$;
create function public.home_create_task(p_operation_id uuid,p_equipment_id text,p_values jsonb) returns public.home_tasks
language sql security invoker set search_path='' as $$select home_private.create_task(p_operation_id,p_equipment_id,p_values);$$;
revoke all on function home_private.create_task(uuid,text,jsonb),public.home_create_task(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function home_private.create_task(uuid,text,jsonb),public.home_create_task(uuid,text,jsonb) to authenticated;
notify pgrst,'reload schema';
