-- =====================================================================
--  PASSO 2 · PROTEÇÃO DOS DADOS (LGPD)  (Central DP ILED · DP ILED PRODUCOES)
--
--  O que este script faz:
--   • Dados do DP e das Notas Fiscais: só quem entrou na Central E está
--     cadastrado como usuário ATIVO no Painel consegue ler ou gravar.
--   • Usuários e permissões: cada pessoa vê só o próprio cadastro; apenas a
--     administradora (master) cria, altera permissões, ativa/desativa e exclui.
--   • Caderno: cada pessoa lê e grava só o PRÓPRIO caderno.
--   • Freelancers NÃO são alterados agora (a página de confirmação do PIX
--     é usada por quem não tem login; vamos tratar isso numa etapa própria).
--
--  Segurança: tudo roda de uma vez só. Se qualquer linha der erro, NADA é
--  alterado (o banco volta sozinho ao estado anterior).
--  Para desfazer depois: rode o arquivo DESFAZER_PROTECAO.sql
-- =====================================================================
begin;

-- trava: só roda se a cópia de segurança (Passo 1) já foi feita
do $$ begin
  if to_regclass('copia_seguranca._regras_antes') is null then
    raise exception 'Rode primeiro o PASSO 1 (1_COPIA_DE_SEGURANCA.sql). Nada foi alterado.';
  end if;
end $$;

-- ---------- funções de apoio ----------
-- a pessoa logada está cadastrada e ativa no Painel?
create or replace function public.usuario_ativo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.dp_usuarios u
    where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and coalesce((to_jsonb(u) ->> 'ativo')::boolean, true)
  );
$$;

-- a pessoa logada é a administradora (master)?
create or replace function public.eh_master() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.dp_usuarios u
    where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and coalesce((to_jsonb(u) ->> 'master')::boolean, false)
  );
$$;

revoke all on function public.usuario_ativo() from public, anon;
revoke all on function public.eh_master() from public, anon;
grant execute on function public.usuario_ativo() to authenticated;
grant execute on function public.eh_master() to authenticated;

-- ---------- limpa as regras antigas e liga a proteção ----------
do $$
declare t text; p record;
begin
  foreach t in array array['dp_colaboradores','dp_ferias','dp_rescisoes','dp_folha','dp_custos',
                           'dp_config','dp_acessos','dp_logs','kv_store','dp_usuarios',
                           'nf_empresas','nf_colaboradores','nf_notas'] loop
    if to_regclass(format('public.%I', t)) is null then continue; end if;
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- ---------- dados do DP e das Notas Fiscais: só usuários ativos ----------
do $$
declare t text;
begin
  foreach t in array array['dp_colaboradores','dp_ferias','dp_rescisoes','dp_folha','dp_custos',
                           'dp_config','dp_acessos','dp_logs','nf_empresas','nf_colaboradores','nf_notas'] loop
    if to_regclass(format('public.%I', t)) is null then continue; end if;
    execute format('create policy "somente_usuarios_ativos" on public.%I for all to authenticated
                    using (public.usuario_ativo()) with check (public.usuario_ativo())', t);
  end loop;
end $$;

-- ---------- kv_store (Lançamentos, Caderno, checklist): caderno é individual ----------
do $$ begin
  if to_regclass('public.kv_store') is not null then
    create policy "kv_somente_usuarios_ativos" on public.kv_store for all to authenticated
      using (public.usuario_ativo()
             and (storage_key not like 'caderno%' or split_part(storage_key, ':', 2) = auth.uid()::text))
      with check (public.usuario_ativo()
             and (storage_key not like 'caderno%' or split_part(storage_key, ':', 2) = auth.uid()::text));
  end if;
end $$;

-- ---------- usuários e permissões ----------
create policy "usuarios_ver_o_proprio_ou_master" on public.dp_usuarios for select to authenticated
  using (lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')) or public.eh_master());
create policy "usuarios_alterar_o_proprio_ou_master" on public.dp_usuarios for update to authenticated
  using (lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')) or public.eh_master())
  with check (lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')) or public.eh_master());
create policy "usuarios_criar_so_master" on public.dp_usuarios for insert to authenticated
  with check (public.eh_master());
create policy "usuarios_excluir_so_master" on public.dp_usuarios for delete to authenticated
  using (public.eh_master());

-- quem não é master pode atualizar o próprio cadastro (ex.: último acesso),
-- mas NÃO consegue mudar permissões, master, ativo, bloqueado nem e-mail
create or replace function public.proteger_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare o jsonb := to_jsonb(old); n jsonb := to_jsonb(new); c text;
begin
  if auth.uid() is not null and not public.eh_master() then
    foreach c in array array['master','permissoes','ativo','bloqueado','email'] loop
      if o ? c then n := jsonb_set(n, array[c], o -> c); end if;
    end loop;
    new := jsonb_populate_record(new, n);
  end if;
  return new;
end $$;
drop trigger if exists proteger_usuario on public.dp_usuarios;
create trigger proteger_usuario before update on public.dp_usuarios
  for each row execute function public.proteger_usuario();

commit;

-- ---------- resultado: situação de cada tabela ----------
select c.relname as tabela,
       case when c.relname = 'dp_freelancers' then '🟡 Mantida como estava (próxima etapa)'
            when not c.relrowsecurity then '🔴 ABERTA'
            else '🟢 Protegida' end as situacao,
       (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) as regras
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by 2, 1;
