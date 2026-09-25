-- =====================================================================
--  DESFAZER · volta as regras de acesso EXATAMENTE como estavam antes do Passo 2
--  (usa a cópia feita no Passo 1). Não mexe em nenhum dado.
-- =====================================================================
begin;

do $$
declare t text; p record; alvo text[] := array['dp_colaboradores','dp_ferias','dp_rescisoes','dp_folha','dp_custos',
        'dp_config','dp_acessos','dp_logs','kv_store','dp_usuarios','nf_empresas','nf_colaboradores','nf_notas'];
begin
  if to_regclass('copia_seguranca._regras_antes') is null then
    raise exception 'Não encontrei a cópia do Passo 1. Nada foi alterado.';
  end if;
  -- 1) tira as regras novas
  foreach t in array alvo loop
    if to_regclass(format('public.%I', t)) is null then continue; end if;
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
  end loop;
  -- 2) recria as regras antigas
  for p in select * from copia_seguranca._regras_antes where tablename = any(alvo) loop
    if to_regclass(format('public.%I', p.tablename)) is null then continue; end if;
    execute format('create policy %I on public.%I as %s for %s to %s %s %s',
      p.policyname, p.tablename, p.permissive, p.cmd,
      (select string_agg(case when r = 'public' then 'public' else quote_ident(r) end, ', ') from unnest(p.roles) r),
      case when p.qual is not null then 'using (' || p.qual || ')' else '' end,
      case when p.with_check is not null then 'with check (' || p.with_check || ')' else '' end);
  end loop;
  -- 3) proteção ligada/desligada como era antes
  for p in select * from copia_seguranca._protecao_antes where tabela = any(alvo) loop
    if to_regclass(format('public.%I', p.tabela)) is null then continue; end if;
    if p.protecao_ligada then execute format('alter table public.%I enable row level security', p.tabela);
    else execute format('alter table public.%I disable row level security', p.tabela); end if;
  end loop;
end $$;

drop trigger if exists proteger_usuario on public.dp_usuarios;

commit;

select 'Tudo voltou como era antes ✅' as resultado;
