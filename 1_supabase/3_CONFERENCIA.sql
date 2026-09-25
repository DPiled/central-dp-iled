-- =====================================================================
--  CENTRAL DP ILED · Diagnóstico de segurança (LGPD)
--  Projeto: DP ILED PRODUCOES
--
--  ✅ ESTA CONSULTA SÓ LÊ. Ela não altera, não apaga e não cria nada.
--
--  Como usar: Supabase → SQL Editor → New query → colar tudo → Run
--  Depois, copie o resultado (botão "Export" → "Copy as CSV")
--  ou tire um print da tabela inteira e mande no chat.
-- =====================================================================

with regras as (
  select
    tablename,
    count(*)                                                    as qtd,
    bool_or(roles && array['anon','public']::name[])            as tem_regra_para_anonimo,
    bool_or(coalesce(qual,'') in ('true','(true)'))              as tem_regra_liberada_geral,
    string_agg(
      policyname || '  [' || cmd || ' | para: ' || array_to_string(roles, ',') ||
      ' | condição: ' || coalesce(qual, '-') || ']',
      E'\n' order by policyname
    )                                                           as detalhes
  from pg_policies
  where schemaname = 'public'
  group by tablename
)
select
  c.relname                                                     as tabela,
  case
    when not c.relrowsecurity                                   then '🔴 ABERTA (sem proteção)'
    when coalesce(r.qtd,0) = 0                                  then '⚪ Trancada (ninguém acessa)'
    when r.tem_regra_para_anonimo                               then '🟠 Aberta para quem não fez login'
    else                                                             '🟢 Só para quem fez login'
  end                                                           as situacao,
  case when c.relrowsecurity then 'sim' else 'não' end          as protecao_ligada,
  coalesce(r.qtd, 0)                                            as qtd_regras,
  case when has_table_privilege('anon', c.oid, 'SELECT')
       then 'sim' else 'não' end                                as anonimo_tem_permissao_de_leitura,
  greatest(c.reltuples, 0)::bigint                              as linhas_aprox,
  coalesce(r.detalhes, '— nenhuma regra —')                     as regras_atuais
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join regras r on r.tablename = c.relname
where n.nspname = 'public'
  and c.relkind = 'r'
order by
  case
    when not c.relrowsecurity then 1
    when r.tem_regra_para_anonimo then 2
    when coalesce(r.qtd,0) = 0 then 3
    else 4
  end,
  c.relname;
