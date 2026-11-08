-- Controle Financeiro, versão 41: faturas de cartão marcadas como pagas ("Paguei").
-- Uma linha por cartão e mês da fatura. Serve só para o aviso "Faturas a pagar" sumir nos dois aparelhos;
-- não cria lançamento (as compras do cartão já estão no app).
-- Mesma segurança das outras tabelas: cada usuário só vê as próprias linhas e só com a verificação em duas etapas (aal2).
-- Rodar uma vez no Supabase, ANTES de publicar a versão 41: SQL Editor > New query > colar tudo > Run.
-- Pode rodar de novo sem problema (não duplica nada). Não apaga nem altera nenhum dado.

begin;

create table if not exists public.faturas_pagas (
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id           text not null,
  cartao_id    text not null,
  competencia  text not null check (competencia ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  pago_em      timestamptz not null default now(),
  primary key (user_id, id)
);

alter table public.faturas_pagas enable row level security;
alter table public.faturas_pagas force row level security;
revoke all on public.faturas_pagas from anon, authenticated;
grant select, insert, update, delete on public.faturas_pagas to authenticated;

drop policy if exists "dono le" on public.faturas_pagas;
drop policy if exists "dono cria" on public.faturas_pagas;
drop policy if exists "dono altera" on public.faturas_pagas;
drop policy if exists "dono apaga" on public.faturas_pagas;
drop policy if exists "exige duas etapas" on public.faturas_pagas;
create policy "dono le" on public.faturas_pagas for select to authenticated using ((select auth.uid()) = user_id);
create policy "dono cria" on public.faturas_pagas for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "dono altera" on public.faturas_pagas for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "dono apaga" on public.faturas_pagas for delete to authenticated using ((select auth.uid()) = user_id);
create policy "exige duas etapas" on public.faturas_pagas as restrictive for all to authenticated
  using ((select auth.jwt() ->> 'aal') = 'aal2') with check ((select auth.jwt() ->> 'aal') = 'aal2');

commit;

-- Conferência: deve mostrar a tabela com RLS ligada e forçada, 5 regras e 0 linhas
select c.relname as tabela, c.relrowsecurity as rls_ligada, c.relforcerowsecurity as rls_forcada,
  (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = 'faturas_pagas') as regras,
  (select count(*) from public.faturas_pagas) as linhas
from pg_class c where c.oid = 'public.faturas_pagas'::regclass;
