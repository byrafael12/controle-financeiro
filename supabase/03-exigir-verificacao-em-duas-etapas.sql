-- Controle Financeiro, Entrega 5.8: o banco só entrega e aceita dados de quem passou
-- pela verificação em duas etapas (login com senha + código do Google Authenticator = "aal2").
-- Só com a senha (sem o código), as tabelas ficam vazias e nada é gravado.
-- Rodar uma vez no Supabase: SQL Editor > New query > colar tudo > Run.
-- IMPORTANTE: rodar DEPOIS de ativar a verificação em duas etapas no app (v18) e de
-- colocar a TOTP_CHAVE no script do backup automático.
-- Para desfazer: rodar o bloco do final (comentado).

do $$
declare
  t text;
begin
  foreach t in array array['categorias', 'cartoes', 'contas_fixas', 'lancamentos',
                           'orcamentos', 'geracoes', 'config', 'backups']
  loop
    execute format('drop policy if exists "exige duas etapas" on public.%I', t);
    execute format(
      'create policy "exige duas etapas" on public.%I as restrictive for all to authenticated '
      'using ((select auth.jwt() ->> ''aal'') = ''aal2'') with check ((select auth.jwt() ->> ''aal'') = ''aal2'')', t);
  end loop;
end;
$$;

-- Para desfazer (só se precisar):
-- do $$ declare t text; begin
--   foreach t in array array['categorias','cartoes','contas_fixas','lancamentos','orcamentos','geracoes','config','backups']
--   loop execute format('drop policy if exists "exige duas etapas" on public.%I', t); end loop;
-- end; $$;
