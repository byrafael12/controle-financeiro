-- Controle Financeiro, Entrega 5.8: fecha a função criada pelo Supabase para o "RLS automático".
-- O Security Advisor apontou (avisos 0028 e 0029) que ela podia ser chamada pela API por visitantes
-- e por usuários logados. O gatilho continua funcionando: o banco o aciona sem essa permissão.
-- Rodado no SQL Editor em 25/10/2026. Resultado: visitante_pode = false, logado_pode = false.

revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

select has_function_privilege('anon', 'public.rls_auto_enable()', 'execute') as visitante_pode,
       has_function_privilege('authenticated', 'public.rls_auto_enable()', 'execute') as logado_pode;
