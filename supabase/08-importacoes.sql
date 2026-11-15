-- Controle Financeiro, versão 47: gravar a importação de fatura ou extrato, com "Desfazer esta importação".
-- Cria a tabela importacoes (uma linha por importação gravada, com o que foi criado e a versão de antes do que foi corrigido)
-- e a coluna importacao_id em lancamentos (de qual importação o lançamento veio ou foi corrigido; vazia nos que já existem).
-- Mesma segurança das outras tabelas: cada usuário só vê as próprias linhas e só com a verificação em duas etapas (aal2).
-- Rodar uma vez no Supabase, ANTES de publicar a versão 47: SQL Editor > New query > colar tudo > Run.
-- Pode rodar de novo sem problema. Não apaga nem altera nenhum dado.

begin;

create table if not exists public.importacoes (
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id           text not null,
  criado_em    timestamptz not null default now(),
  arquivo      text not null,
  tipo         text not null check (tipo in ('fatura', 'extrato')),
  cartao_id    text,
  competencia  text check (competencia is null or competencia ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  resumo       jsonb not null default '{}'::jsonb,
  desfazer     jsonb not null default '{}'::jsonb,
  desfeita_em  timestamptz,
  primary key (user_id, id)
);

alter table public.importacoes enable row level security;
alter table public.importacoes force row level security;
revoke all on public.importacoes from anon, authenticated;
grant select, insert, update, delete on public.importacoes to authenticated;

drop policy if exists "dono le" on public.importacoes;
drop policy if exists "dono cria" on public.importacoes;
drop policy if exists "dono altera" on public.importacoes;
drop policy if exists "dono apaga" on public.importacoes;
drop policy if exists "exige duas etapas" on public.importacoes;
create policy "dono le" on public.importacoes for select to authenticated using ((select auth.uid()) = user_id);
create policy "dono cria" on public.importacoes for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "dono altera" on public.importacoes for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "dono apaga" on public.importacoes for delete to authenticated using ((select auth.uid()) = user_id);
create policy "exige duas etapas" on public.importacoes as restrictive for all to authenticated
  using ((select auth.jwt() ->> 'aal') = 'aal2') with check ((select auth.jwt() ->> 'aal') = 'aal2');

alter table public.lancamentos add column if not exists importacao_id text;

commit;

-- Conferência: deve mostrar importacoes | true | true | 5 | 0 | 1
select c.relname as tabela, c.relrowsecurity as rls_ligada, c.relforcerowsecurity as rls_forcada,
  (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = 'importacoes') as regras,
  (select count(*) from public.importacoes) as linhas,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'lancamentos' and column_name = 'importacao_id') as coluna_nova
from pg_class c where c.oid = 'public.importacoes'::regclass;
