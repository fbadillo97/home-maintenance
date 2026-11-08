-- Synthetic fixtures only; always rolled back. No real member details in this file.
begin;
insert into auth.users(id,email,email_confirmed_at) values('11111111-1111-4111-8111-111111111111','home-owner-test@example.invalid',now()),('22222222-2222-4222-8222-222222222222','home-unlisted-test@example.invalid',now()),('33333333-3333-4333-8333-333333333333','home-unverified-test@example.invalid',null);
insert into home_private.members(email) values('home-owner-test@example.invalid'),('home-unverified-test@example.invalid');
insert into public.home_equipment(id,name,serial_number) values('test-equipment','Synthetic fixture','000123');
insert into public.home_tasks(id,title,recurrence_unit,recurrence_interval) values('test-task','Synthetic maintenance','months',1);
insert into public.home_task_equipment values('test-task','test-equipment');
insert into public.home_attention(id,equipment_id,question) values('test-attention','test-equipment','Synthetic follow-up');
insert into public.home_documents(id,title,filename,content_type) values('test-document','Synthetic PDF','test.pdf','application/pdf');
insert into home_private.document_files values('test-document',decode('AAEC','base64'));
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}',true);
do $$declare e public.home_equipment; result text; count_before integer;begin
 if not public.home_access() then raise exception 'Approved owner denied';end if;
 if not exists(select 1 from public.home_equipment where id='test-equipment') then raise exception 'Approved SELECT denied';end if;
 e:=public.home_save_equipment('test-equipment',1,'{"name":"Edited synthetic","serial_number":"000123","ownership_date":"2024-10","warranty_status":"unknown","manual_url":"https://example.invalid/manual.pdf"}');
 if e.revision<>2 or e.serial_number<>'000123' or e.ownership_date<>'2024-10' then raise exception 'Equipment save corrupted values';end if;
 begin perform public.home_save_equipment('test-equipment',1,'{"name":"Old save"}');raise exception 'Stale save accepted';exception when sqlstate '40001' then null;end;
 begin perform public.home_save_equipment('test-equipment',2,'{"name":"Invalid date","ownership_date":"2025-13"}');raise exception 'Invalid date accepted';exception when raise_exception then if sqlerrm='Invalid date accepted' then raise;end if;end;
 begin update public.home_equipment set notes='unauthorized direct write' where id='test-equipment';raise exception 'Direct write accepted';exception when insufficient_privilege then null;end;
 perform public.home_save_attention('test-attention',1,'resolved','Confirmed by synthetic test');
 begin perform public.home_save_attention('test-attention',1,'open','');raise exception 'Stale attention accepted';exception when sqlstate '40001' then null;end;
 if public.home_document('test-document')->>'base64'<>'AAEC' then raise exception 'Document bytes changed';end if;
 result:=public.home_log_work('44444444-4444-4444-8444-444444444444','maintenance',current_date::text,'Synthetic completion',array['test-equipment'],'Owner',null,null,'test-task',1,(current_date+30));
 perform public.home_log_work('44444444-4444-4444-8444-444444444444','maintenance',current_date::text,'Synthetic completion',array['test-equipment'],'Owner',null,null,'test-task',1,(current_date+30));
 if (select count(*) from public.home_history where id=result)<>1 then raise exception 'Retry duplicated completion';end if;
 if (select revision from public.home_tasks where id='test-task')<>2 then raise exception 'Task revision wrong';end if;
 begin perform public.home_log_work('55555555-5555-4555-8555-555555555555','maintenance',current_date::text,'Stale task completion',array['test-equipment'],null,null,null,'test-task',1,null);raise exception 'Stale task accepted';exception when sqlstate '40001' then null;end;
 if exists(select 1 from public.home_history where id='55555555-5555-4555-8555-555555555555') then raise exception 'Failed task created history';end if;
 perform public.home_log_work('66666666-6666-4666-8666-666666666666','modification','2025-03','Synthetic remodel',array['test-equipment']);
end;$$;
select set_config('request.jwt.claims','{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated","user_metadata":{"role":"owner"}}',true);
do $$begin
 if public.home_access() then raise exception 'Unlisted account gained access';end if;
 if exists(select 1 from public.home_equipment) then raise exception 'Unlisted account read equipment';end if;
 begin perform public.home_document('test-document');raise exception 'Unlisted account read document';exception when insufficient_privilege then null;end;
 begin perform public.home_save_equipment('test-equipment',2,'{"name":"Blocked"}');raise exception 'Unlisted account wrote equipment';exception when insufficient_privilege then null;end;
end;$$;
select set_config('request.jwt.claims','{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}',true);
do $$begin if public.home_access() then raise exception 'Unconfirmed account gained access';end if;end;$$;
set local role anon;
do $$begin
 begin perform public.home_access();raise exception 'Anonymous RPC allowed';exception when insufficient_privilege then null;end;
 begin perform count(*) from public.home_equipment;raise exception 'Anonymous table access allowed';exception when insufficient_privilege then null;end;
end;$$;
reset role;
rollback;
select 'PASS: verified membership, RLS, direct-write denial, field preservation, stale-save rejection, logging, retry idempotency, document privacy and anonymous/unlisted/unverified denial' as result;
