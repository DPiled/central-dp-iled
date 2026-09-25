-- =====================================================================
--  PASSO 4 · CADASTRO ÚNICO  (rodar DEPOIS dos passos 1, 2 e 3)
--
--  • Cria o campo "Também emite nota fiscal?" no cadastro de colaboradores
--    (para os internos/CLT que emitem NF, dependendo da função).
--  • Deixa as 5 empresas do Grupo ILED com o CNPJ correto no sistema de
--    Notas Fiscais, usando os mesmos nomes do Painel DP.
--  Não apaga nada. Pode rodar mais de uma vez.
-- =====================================================================
begin;

alter table public.dp_colaboradores add column if not exists emite_nf text;

do $$
declare
  e record; achou text;
  norm text := 'upper(regexp_replace(translate(replace(%s,''-'','' ''),''ÁÀÂÃÉÊÍÓÔÕÚÇáàâãéêíóôõúç'',''AAAAEEIOOOUCaaaaeeiooouc''),''\s+'','' '',''g''))';
begin
  if to_regclass('public.nf_empresas') is null then return; end if;
  for e in select * from (values
      ('ILED BRASILIA',   '19.751.595/0001-45', array['ILED','ILED BRASILIA','ILED BSB','ILED DF']),
      ('ILED SÃO PAULO',  '49.331.067/0001-06', array['ILED SP','ILED SAO PAULO']),
      ('NEW ILED',        '28.987.045/0001-10', array['NEW ILED','NEWILED','NEW']),
      ('RED PRODUCOES',   '11.246.351/0001-01', array['RED','RED PRODUCOES']),
      ('X-LED PRODUCOES', '66.023.926/0001-00', array['X LED','XLED','X LED PRODUCOES']))
      as t(nome, cnpj, apelidos) loop
    -- 1º procura pelo CNPJ; 2º pelo nome (ou apelido); se não achar, cria
    select id into achou from public.nf_empresas
      where regexp_replace(coalesce(cnpj,''),'\D','','g') = regexp_replace(e.cnpj,'\D','','g') limit 1;
    if achou is null then
      execute format('select id from public.nf_empresas where '||format(norm,'nome')||' = any($1) limit 1')
        into achou using e.apelidos || array[upper(translate(e.nome,'ÃÁ','AA'))];
    end if;
    if achou is not null then
      update public.nf_empresas set nome = e.nome, cnpj = e.cnpj where id = achou;
    else
      insert into public.nf_empresas (id, nome, cnpj) values ('emp-' || regexp_replace(e.cnpj,'\D','','g'), e.nome, e.cnpj);
    end if;
  end loop;
end $$;

commit;

select 'Cadastro único preparado ✅' as resultado,
       (select count(*) from public.nf_empresas) as empresas_nas_notas_fiscais;
