-- Controle Financeiro, Entrega 5.4: ajuste na tabela de cópias de segurança.
-- O app guarda uma cópia automática antes de restaurar um backup (tipo "antes-restauracao").
-- Rodar uma vez no Supabase: SQL Editor > New query > colar tudo > Run.

alter table public.backups drop constraint backups_tipo_check;
alter table public.backups add constraint backups_tipo_check
  check (tipo in ('semanal', 'mensal', 'manual', 'antes-restauracao'));
