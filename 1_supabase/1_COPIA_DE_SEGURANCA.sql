-- =====================================================================
--  PASSO 1 · CÓPIA DE SEGURANÇA  (Central DP ILED · projeto DP ILED PRODUCOES)
--
--  Copia TODAS as tabelas e TODAS as regras de acesso atuais para uma
--  área separada chamada "copia_seguranca". Não altera nada do que existe.
--  Essa área não fica visível para os sistemas nem para a internet.
--  Pode rodar mais de uma vez sem problema (não sobrescreve a primeira cópia).
-- =====================================================================

create schema if not exists copia_seguranca;

-- 1) cópia dos dados de cada tabela
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    if to_regclass(format('copia_seguranca.%I', t.tablename)) is null then
      execute format('create table copia_seguranca.%I as table public.%I', t.tablename, t.tablename);
    end if;
  end loop;
end $$;

-- 2) cópia das regras de acesso e de quais tabelas tinham proteção ligada
create table if not exists copia_seguranca._regras_antes as
  select now() as copiado_em, p.* from pg_policies p where p.schemaname = 'public';

create table if not exists copia_seguranca._protecao_antes as
  select now() as copiado_em, c.relname::text as tabela, c.relrowsecurity as protecao_ligada
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r';

-- 3) resultado: deve aparecer "Cópia feita" com o número de tabelas copiadas
select 'Cópia feita ✅' as resultado,
       (select count(*) from pg_tables where schemaname = 'copia_seguranca' and tablename not like '\_%') as tabelas_copiadas,
       (select count(*) from copia_seguranca._regras_antes) as regras_guardadas;
