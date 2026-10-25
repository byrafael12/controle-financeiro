-- Controle Financeiro, Entrega 5.2: tabelas e segurança (RLS)
-- Rodar uma vez no Supabase: SQL Editor > New query > colar tudo > Run.
-- Cada linha de cada tabela pertence a um usuário (user_id). A RLS garante que
-- cada pessoa logada só lê e grava as próprias linhas. Visitante sem login não acessa nada.
-- Valores sempre em centavos inteiros. Datas no formato do banco (date) e
-- competência como texto AAAA-MM, iguais ao app atual.

begin;

-- Atualiza "atualizado_em" sozinho a cada alteração
create or replace function public.tocar_atualizado_em()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

-- Categorias de receita e despesa
create table public.categorias (
  user_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id       text not null,
  tipo     text not null check (tipo in ('receita', 'despesa')),
  nome     text not null check (char_length(nome) between 1 and 60),
  cor      text not null default '#888888' check (cor ~ '^#[0-9a-fA-F]{6}$'),
  ordem    integer not null default 0,
  ativa    boolean not null default true,
  primary key (user_id, id)
);

-- Cartões de crédito
create table public.cartoes (
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id                 text not null,
  nome               text not null check (char_length(nome) between 1 and 40),
  dia_melhor_compra  smallint not null check (dia_melhor_compra between 1 and 31),
  dia_vencimento     smallint not null check (dia_vencimento between 1 and 31),
  ordem              integer not null default 0,
  ativo              boolean not null default true,
  primary key (user_id, id)
);

-- Contas fixas (modelo que gera as previstas de cada mês)
create table public.contas_fixas (
  user_id                  uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id                       text not null,
  descricao                text not null check (char_length(descricao) between 1 and 80),
  categoria_id             text not null,
  forma_pagamento          text not null,
  cartao_id                text,
  dia_vencimento           smallint not null check (dia_vencimento between 1 and 31),
  valor_estimado_centavos  bigint not null check (valor_estimado_centavos >= 0),
  ativa                    boolean not null default true,
  primary key (user_id, id)
);

-- Lançamentos (receitas e despesas, inclusive parcelas e contas fixas geradas)
create table public.lancamentos (
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id               text not null,
  tipo             text not null check (tipo in ('receita', 'despesa')),
  descricao        text not null check (char_length(descricao) between 1 and 120),
  valor_centavos   bigint not null check (valor_centavos >= 0),
  data             date not null,
  competencia      text not null check (competencia ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  categoria_id     text not null,
  forma_pagamento  text not null,
  cartao_id        text,
  status           text not null default 'paga' check (status in ('paga', 'prevista')),
  parcela          jsonb,
  grupo_parcela    text,
  conta_fixa_id    text,
  reembolso        jsonb,
  reembolso_quem   text,
  reembolso_de     text,
  observacao       text not null default '' check (char_length(observacao) <= 500),
  origem           text,
  versao_esquema   smallint not null default 1,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  primary key (user_id, id)
);
create index lancamentos_competencia_idx on public.lancamentos (user_id, competencia);
create index lancamentos_data_idx on public.lancamentos (user_id, data);
create index lancamentos_grupo_idx on public.lancamentos (user_id, grupo_parcela) where grupo_parcela is not null;
create trigger lancamentos_atualizado_em before update on public.lancamentos
  for each row execute function public.tocar_atualizado_em();

-- Orçamento manual por categoria (o automático é calculado no app)
create table public.orcamentos (
  user_id                  uuid not null default auth.uid() references auth.users (id) on delete cascade,
  categoria_id             text not null,
  valor_planejado_centavos bigint not null check (valor_planejado_centavos > 0),
  primary key (user_id, categoria_id)
);

-- Meses em que as contas fixas já foram geradas (evita gerar duas vezes)
create table public.geracoes (
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  mes            text not null check (mes ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  contas         text[] not null default '{}',
  atualizado_em  timestamptz not null default now(),
  primary key (user_id, mes)
);
create trigger geracoes_atualizado_em before update on public.geracoes
  for each row execute function public.tocar_atualizado_em();

-- Configuração geral (uma linha por usuário)
create table public.config (
  user_id                uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  fixas_desde            text check (fixas_desde ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  ultimo_backup_baixado  timestamptz,
  versao_esquema         smallint not null default 1,
  criado_em              timestamptz not null default now()
);

-- Cópias de segurança dentro do banco (semanais e mensais, geradas pelo app)
create table public.backups (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id         text not null,
  tipo       text not null check (tipo in ('semanal', 'mensal', 'manual')),
  gerado_em  timestamptz not null default now(),
  dados      jsonb not null,
  primary key (user_id, id)
);

-- Segurança: liga a RLS, fecha tudo para visitante sem login e libera
-- para o usuário logado só as linhas dele.
do $$
declare
  t text;
begin
  foreach t in array array['categorias', 'cartoes', 'contas_fixas', 'lancamentos',
                           'orcamentos', 'geracoes', 'config', 'backups']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format(
      'create policy "dono le" on public.%I for select to authenticated using ((select auth.uid()) = user_id)', t);
    execute format(
      'create policy "dono cria" on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)', t);
    execute format(
      'create policy "dono altera" on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t);
    execute format(
      'create policy "dono apaga" on public.%I for delete to authenticated using ((select auth.uid()) = user_id)', t);
  end loop;
end;
$$;

revoke execute on function public.tocar_atualizado_em() from public, anon, authenticated;

commit;
