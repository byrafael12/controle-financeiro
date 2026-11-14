-- Controle Financeiro, versão 42: consumo do gás em m³ e total faturado em kg (conta Gás Supergasbras).
-- Duas colunas novas em lancamentos, vazias em todos os lançamentos que já existem.
-- Rodar uma vez no Supabase, ANTES de publicar a versão 42: SQL Editor > New query > colar tudo > Run.
-- Pode rodar de novo sem problema. Não apaga nem altera nenhum dado. A segurança da tabela (RLS e duas etapas) continua a mesma.

begin;

alter table public.lancamentos add column if not exists consumo_m3 numeric(8,3);
alter table public.lancamentos add column if not exists faturado_kg numeric(8,3);

alter table public.lancamentos drop constraint if exists lancamentos_consumo_m3_positivo;
alter table public.lancamentos add constraint lancamentos_consumo_m3_positivo check (consumo_m3 is null or consumo_m3 > 0);
alter table public.lancamentos drop constraint if exists lancamentos_faturado_kg_positivo;
alter table public.lancamentos add constraint lancamentos_faturado_kg_positivo check (faturado_kg is null or faturado_kg > 0);

commit;

-- Conferência: deve mostrar as 2 colunas e "preenchidos" = 0
select column_name as coluna, data_type as tipo,
  (select count(*) from public.lancamentos where consumo_m3 is not null or faturado_kg is not null) as preenchidos
from information_schema.columns
where table_schema = 'public' and table_name = 'lancamentos' and column_name in ('consumo_m3', 'faturado_kg')
order by column_name;
